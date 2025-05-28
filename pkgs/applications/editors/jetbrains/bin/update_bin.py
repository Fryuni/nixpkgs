#! /usr/bin/env nix-shell
#! nix-shell -i python3 -p python3 python3.pkgs.packaging python3.pkgs.requests python3.pkgs.xmltodict
import json
import pathlib
import logging
import requests
import subprocess
import sys
from urllib.error import HTTPError
import urllib.request
import xmltodict
from collections import ChainMap
from packaging import version
from pprint import pprint
from os import environ, mkdir

updates_url = "https://www.jetbrains.com/updates/updates.xml"
current_path = pathlib.Path(__file__).parent
versions_file_path = current_path.joinpath("versions.json").resolve()

debug_outputs_path = current_path.joinpath("outputs").resolve()
if not debug_outputs_path.exists():
    debug_outputs_path.mkdir()

available_channels_path = current_path.joinpath("outputs", "available_channels.json")

fromVersions = {}
toVersions = {}

logging.basicConfig(stream=sys.stdout, level=logging.DEBUG)


def one_or_more(x):
    return x if isinstance(x, list) else [x]


def download_channels():
    logging.info("Checking for updates from %s", updates_url)
    updates_response = requests.get(updates_url)
    updates_response.raise_for_status()
    root = xmltodict.parse(updates_response.text)
    products = root["products"]["product"]
    by_channel = {
        channel["@name"]: {
            **product,
            'channel': [channel]
        }
        for product in products
        if "channel" in product
        for channel in one_or_more(product["channel"])
    }
    by_product = {
        product["@name"]: product
        for product in products
        if "channel" in product
        for channel in one_or_more(product["channel"])
    }

    return {**by_channel, **by_product}


def build_version(build):
    build_number = build["@fullNumber"] if "@fullNumber" in build else build["@number"]
    return version.parse(build_number)


def latest_build(product_channel):
    builds = [
        (channel, build)
        for channel in one_or_more(product_channel["channel"])
        if environ.get('USE_EAP') == 'True' or channel['@status'] != 'eap'
        for build in one_or_more(channel["build"])
    ]
    latest = max(builds, key=lambda p: build_version(p[1]))
    return latest

sha256memo = {}

def download_sha256(url):
    # Memoization for multiple architectures
    if url in sha256memo:
        return sha256memo[url]

    url = f"{url}.sha256"
    download_response = requests.get(url)
    download_response.raise_for_status()
    sha256 = download_response.content.decode('UTF-8').split(' ')[0]
    sha256memo[url] = sha256
    return sha256


channels = download_channels()

with available_channels_path.open("w") as channels_fh:
    json.dump(sorted(list(channels.keys())), channels_fh, indent=2)

with debug_outputs_path.joinpath("channels.json").open("w") as channels_fh:
    json.dump(channels, channels_fh, indent=2)


def get_url(template, version_or_build_number, version_number):
    release = [str(n) for n in version.parse(version_number).release]
    for k in range(len(release), 0, -1):
        s = ".".join(release[0:k])
        url = template.format(version=version_or_build_number, versionMajorMinor=s)
        try:
            if urllib.request.urlopen(url).getcode() == 200:
                return url
        except HTTPError:
            pass
    return None


def update_product(name, product):
    update_channel = product["update-channel"]
    logging.info("Updating %s", name)
    channel = channels.get(update_channel)
    if channel is None:
        logging.error("Failed to find channel %s.", update_channel)
        logging.error("Check that the update-channel in %s matches the name in %s", versions_file_path, updates_url)
        return

    try:
        channel, build = latest_build(channel)
        new_version = build["@version"]
        new_build_number = build["@fullNumber"]
        new_build_number = ""
        if "@fullNumber" not in build:
            new_build_number = build["@number"]
        else:
            new_build_number = build["@fullNumber"]
        if "EAP" not in channel["@name"]:
            version_or_build_number = new_version
        else:
            version_or_build_number = new_build_number
        version_number = new_version.split(' ')[0]
        download_url = product["url-template"].format(version=version_or_build_number, versionMajorMinor=version_number)
        product["url"] = download_url
        if "sha256" not in product or product.get("build_number") != new_build_number:
            fromVersions[name] = product["version"]
            toVersions[name] = new_version
            logging.info("Found a newer version %s with build number %s.", new_version, new_build_number)
            product["version"] = new_version
            product["build_number"] = new_build_number
            product["sha256"] = download_sha256(download_url)
        else:
            logging.info("Already at the latest version %s with build number %s.", new_version, new_build_number)
    except Exception as e:
        logging.exception("Update failed:", exc_info=e)
        logging.warning("Skipping %s due to the above error.", name)
        logging.warning("It may be out-of-date. Fix the error and rerun.")


def update_products(products):
    for name, product in products.items():
        update_product(name, product)


with versions_file_path.open("r") as versions_file:
    versions = json.load(versions_file)

products = {**ChainMap(*versions.values())}
update_products(products)

versions = {
    arch: products
    for arch in versions.keys()
}

with versions_file_path.open("w") as versions_file:
    json.dump(versions, versions_file, indent=2)
    versions_file.write("\n")

if len(toVersions) != 0:
    if len(toVersions) == 1:
        commitMessage = ""
    else:
        lowestProd, lowestVersion = min(fromVersions.items(), key=lambda p: p[1])
        highestProd, highestVersion = max(toVersions.items(), key=lambda p: p[1])
        commitMessage = f"jetbrains: {lowestProd} ({lowestVersion}) -> {highestProd} ({highestVersion})"
        commitMessage += "\n\n"

    for name in toVersions.keys():
        commitMessage += f"jetbrains.{name}: {fromVersions[name]} -> {toVersions[name]}\n"

    # Commit the result
    logging.info("#### Committing changes... ####")
    subprocess.run(['git', 'commit', f'-m{commitMessage}', '--', f'{versions_file_path}'], check=True)

logging.info("#### Updating plugins ####")
plugin_script = current_path.joinpath("../plugins/update_plugins.py").resolve()
subprocess.call(plugin_script)
