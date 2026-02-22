{
  description = "ctfd-openstack — IaC dev environment (OpenTofu + Ansible + k3s)";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
  };

  outputs = { self, nixpkgs }:
    let
      supportedSystems = [ "x86_64-linux" "aarch64-linux" "aarch64-darwin" "x86_64-darwin" ];
      forAllSystems = nixpkgs.lib.genAttrs supportedSystems;
    in
    {
      devShells = forAllSystems (system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
        in
        {
          default = pkgs.mkShell {
            packages = with pkgs; [
              # ── IaC ──────────────────────────────────────
              opentofu        # >= 1.11（pinned via flake.lock）

              # ── Configuration Management ─────────────────
              ansible
              sshpass         # ansible password-based SSH

              # ── Kubernetes ───────────────────────────────
              kubectl
              kubernetes-helm # k3s workloads

              # ── Scenario builds（Pulumi + Go）─────────────
              go_1_22         # go.mod 要求 go 1.22
              pulumi

              # ── Utilities ────────────────────────────────
              jq
              yq-go           # YAML 處理
              openssh
              gnumake
            ];

            shellHook = ''
              echo "──────────────────────────────────────────"
              echo " ctfd-openstack dev environment"
              echo "──────────────────────────────────────────"
              echo " tofu:    $(tofu version 2>/dev/null | head -1)"
              echo " ansible: $(ansible --version 2>/dev/null | head -1)"
              echo " kubectl: $(kubectl version --client 2>/dev/null | grep -oP 'Client Version: \K.*' || kubectl version --client --short 2>/dev/null)"
              echo " go:      $(go version 2>/dev/null)"
              echo " pulumi:  $(pulumi version 2>/dev/null)"
              echo "──────────────────────────────────────────"

              # 提醒尚未設定 OpenStack 憑證
              if [ ! -f "''${XDG_CONFIG_HOME:-$HOME/.config}/openstack/clouds.yaml" ]; then
                echo ""
                echo " ⚠  ~/.config/openstack/clouds.yaml 不存在"
                echo "    請參考 README.md 設定 OpenStack 連線資訊"
              fi
            '';

            # 確保 ansible 使用 Nix 提供的 Python
            env = {
              ANSIBLE_PYTHON_INTERPRETER = "${pkgs.python3}/bin/python3";
            };
          };
        });
    };
}
