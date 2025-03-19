{
  lib,
  buildGoModule,
  fetchFromGitHub,
  fetchpatch,
}:

buildGoModule rec {
  pname = "k2tf";
  version = "0.8.0";

  src = fetchFromGitHub {
    owner = "sl1pm4t";
    repo = pname;
    rev = "1b376c0c58d6700a61bccb02fae23bbbccb3211d";
    sha256 = "sha256-2HiiVtdwDwlU5xbZ8XqP+7fUBX6hg+ssZ0a4H6bc9qE=";
  };

  vendorHash = "sha256-2QjLiugOwfdyrERi0Uf1UUuKLXsagJdVnfjRPFeOD8k=";

  ldflags = [
    "-s"
    "-w"
    "-X main.version=${version}"
    "-X main.commit=v${version}"
  ];

  meta = with lib; {
    description = "Kubernetes YAML to Terraform HCL converter";
    mainProgram = "k2tf";
    homepage = "https://github.com/sl1pm4t/k2tf";
    license = licenses.mpl20;
    maintainers = [ maintainers.flokli ];
  };
}
