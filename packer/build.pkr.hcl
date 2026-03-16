# Packer build：編排 provisioning 流程
# 流程：base setup → [複製題目檔案] → 題目專屬 scripts → cleanup

build {
  sources = ["source.openstack.challenge"]

  # ── 階段 1：基礎環境設定（所有題目共用）──────────────────
  provisioner "shell" {
    scripts = ["${path.root}/scripts/base-setup.sh"]
  }

  # ── 階段 1b：複製題目檔案到 VM ──────────────────────────
  # 有指定 challenge_files 時，將目錄內容複製到 /tmp/challenge-files/
  # setup.sh 可從此路徑安裝題目程式碼（如 nix build 產出物、原始碼等）
  dynamic "provisioner" {
    labels   = ["file"]
    for_each = var.challenge_files != "" ? [1] : []
    content {
      source      = var.challenge_files
      destination = "/tmp/challenge-files/"
    }
  }

  # ── 階段 2：題目專屬 provisioning scripts ─────────────────
  # 由 challenge.pkrvars.hcl 指定（provision_scripts 變數）
  # 只在有指定 scripts 時執行
  dynamic "provisioner" {
    labels   = ["shell"]
    for_each = length(var.provision_scripts) > 0 ? [1] : []
    content {
      scripts = var.provision_scripts
    }
  }

  # ── 階段 2b：行內 provisioning 指令 ────────────────────
  # 簡單題目不需要獨立 script，直接寫指令
  dynamic "provisioner" {
    labels   = ["shell"]
    for_each = length(var.provision_inline) > 0 ? [1] : []
    content {
      inline = var.provision_inline
    }
  }

  # ── 階段 3：清理（縮小 image 大小、移除暫存）────────────
  provisioner "shell" {
    scripts = ["${path.root}/scripts/cleanup.sh"]
  }

  # ── 階段 4：建立 flag 佔位目錄 ──────────────────────────
  # cloud-init 在 runtime 寫入 per-player flag
  provisioner "shell" {
    inline = [
      "sudo mkdir -p /opt/ctf",
      "echo 'FLAG_PLACEHOLDER' | sudo tee /opt/ctf/flag.txt > /dev/null",
      "sudo chmod 444 /opt/ctf/flag.txt"
    ]
  }
}
