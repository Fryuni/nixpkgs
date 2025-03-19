#!/usr/bin/env nix-shell
#! nix-shell -i bash -p google-cloud-sdk

set -euo pipefail

BUCKET_NAME="${BUCKET_NAME:-nixos-cloud-images}"
IMAGE_FAMILY="${IMAGE_FAMILY:-nixos}"
TIMESTAMP="$(date +%Y%m%d%H%M)"
IMAGE_NAME="${IMAGE_FAMILY}-${TIMESTAMP}"
export TIMESTAMP

nix-build ./nixos/lib/eval-config.nix \
    -A config.system.build.googleComputeImage \
    --arg modules "[ ./nixos/modules/virtualisation/google-compute-image.nix ]" \
    --argstr system x86_64-linux \
    -o gce \
    -j 10

img_path=$(echo gce/*.tar.gz)
img_id=$(echo "$IMAGE_NAME" | sed 's|.raw.tar.gz$||;s|\.|-|g;s|_|-|g')

STORAGE_FILE="gs://${BUCKET_NAME}/$IMAGE_FAMILY/$TIMESTAMP.tar.gz"

if ! gsutil ls "$STORAGE_FILE"; then
    gcloud storage cp "$img_path" "$STORAGE_FILE"
    # gsutil acl ch -u AllUsers:R "gs://${BUCKET_NAME}/$IMAGE_NAME"

    gcloud compute images create \
        "$img_id" \
        --source-uri "$STORAGE_FILE" \
        --family="$IMAGE_FAMILY"
fi
