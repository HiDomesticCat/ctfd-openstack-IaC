# Challenge Instance 壓力測試報告

**日期**: 2026-03-15~16 | **題目**: Web Traversal (VM: 1vCPU/2GB) | **環境**: OpenStack + chall-manager

## 第一輪：修復前（Baseline）

**設定**: `ram_allocation_ratio = 1.0`（預設，不 overcommit）

| 並發 | 啟動成功 | 啟動 (avg) | 關閉 (avg) | 完整週期牆鐘 |
|------|---------|-----------|-----------|-------------|
| 1 | 1/1 | **63.5s** | **15.2s** | 78.8s |
| 3 | 3/3 | **69.4s** | **18.0s** | 89.5s |
| 5 | 5/5 | **80.9s** | **23.4s** | 111.1s |
| 10 | 6/10 | **95.0s** | **17.1s** | 129.4s |
| 15 | 6/15 | **99.2s** | **10.7s** | 127.8s |
| 20 | 6/20 | **115.1s** | **10.0s** | 147.4s |

> 並發 >6 後 VM 進入 ERROR，錯誤: `Failed to retrieve allocations for consumer`

## 第二輪：記憶體修復

**設定**: `ram_allocation_ratio = 1.5`（允許 1.5x 記憶體 overcommit）

| 並發 | 啟動成功 | 啟動 (avg) | 關閉 (avg) | 完整週期牆鐘 |
|------|---------|-----------|-----------|-------------|
| 2 | 2/2 | **66.6s** | **15.9s** | 84.1s |
| 10 | 10/10 | **115.3s** | **29.6s** | 155.3s |
| 15 | 10/15 | **123.0s** | **22.3s** | 167.6s |
| 20 | 11/20 | **141.5s** | **18.9s** | 188.2s |

> 並發 10 全數成功；15/20 超過硬體 RAM 上限仍有部分失敗

## 最終測試（全部優化後）

**設定**: `ram_allocation_ratio = 1.5` + 共用 SG + config-drive + readiness check + kernel/systemd/initramfs 優化

| 並發 | 啟動成功 | 啟動 (avg) | 關閉 (avg) | 完整週期牆鐘 | vs 第一輪 |
|------|---------|-----------|-----------|-------------|----------|
| 1 | 1/1 | **42.3s** | **14.9s** | 57.3s | 啟動 -33%, URL 即用 |
| 3 | 3/3 | **47.9s** | **18.4s** | 68.5s | 啟動 -31% |
| 5 | 5/5 | **58.2s** | **23.3s** | 85.5s | 啟動 -28% |
| 10 | 10/10 | **110.4s** | **14.6s** | 158.5s | 成功率 60%→100% |
| 15 | 8/15 | **103.0s** | **7.1s** | 313.2s | 成功率 40%→53% |
| 20 | 10/20 | **105.2s** | **15.2s** | 147.7s | 成功率 30%→50% |

> 並發 10 全數成功且 URL 回來即可連線；15/20 受硬體 RAM 限制

## 優化詳情

### 第三輪：啟動時間優化

**優化項目**：

| 優化 | 層級 | 預期效果 | 實際效果 |
|------|------|---------|---------|
| 共用 Security Group | Scenario config | 省 SG 建立 ~3-5s | Boot API -3s |
| Readiness check | Scenario Go code | URL 回來即可用 | Service Ready 0.1s（原 33s 等待消除） |
| 停用不必要 services | Packer base image | 省 systemd boot ~10s | Boot -5s |
| Config-drive | Scenario Go code + Packer | 省 DHCP metadata ~20s | **Boot -16s** |
| Image 預熱 | Makefile target | 消除 cold start ~30s | 首次啟動正常 |

**停用的 services**（`base-setup.sh`）：
- snapd（purge，最大 boot 開銷 + 100MB RAM）
- ModemManager、udisks2、multipathd（硬體管理，VM 不需要）
- unattended-upgrades、apt-daily timers（自動更新）
- polkit、man-db.timer、motd-news.timer（雜項）
- nginx（web-example 題目不使用）

**Config-drive 原理**：
- 原本：cloud-init 透過 DHCP → metadata service 取得設定（等待 ~23s）
- 優化：metadata 燒成 ISO 掛載到 VM，cloud-init 直接讀取（<1s）
- 實作：scenario `ConfigDrive: true` + image `datasource_list: [ConfigDrive, OpenStack, None]`

**優化後結果**（單用戶，含 readiness check）：

| 版本 | 啟動 | 玩家體驗 |
|------|------|---------|
| 原始 | 63.5s + 等 ~33s 才能用 | 差（connection refused） |
| + readiness | 68.2s，URL 即用 | 好 |
| + 停用 services | 63.2s，URL 即用 | 好 |
| + config-drive | 46.8s，URL 即用 | 更好 |
| **+ kernel/systemd/initramfs/virtio** | **42.3s，URL 即用** | **最佳（-33%）** |

**console log boot 時間線對比**：

```
原始 image:
0s     7s    13s              36s     39s  41s  ~47s
|──────|──────|───── DHCP ──────|──────|────|────|── service
 kernel  init   init-local→init  init   cfg  fin   challenge
                  (23s 等待!)

最終優化 image（config-drive + kernel cmdline + initramfs lz4 + systemd mask）:
0s     6s   11s 13s    ~18s
|──────|─────|──|──────|── service
 kernel  init  init cfg   challenge
              (config-drive 2s, DHCP 消除)
              (quiet + skip fsck/raid/lvm + lz4 initramfs)
```

**第四輪優化新增項目**（在第三輪基礎上）：

| 優化 | 效果 |
|------|------|
| Kernel cmdline: `quiet loglevel=3 nomodeset raid=noautodetect rd.lvm=0 rd.md=0 fsck.mode=skip` | -1~2s |
| Mask `systemd-networkd-wait-online`（預設 timeout 120s） | -2~5s |
| Mask `plymouth`, `lvm2-monitor`, `packagekit`, `accounts-daemon` | -1s |
| Initramfs: `MODULES=dep` + `COMPRESS=lz4` | -0.5~1s |
| systemd timeout: `DefaultTimeoutStartSec=10s`（原 90s） | 防止卡住 |
| Glance image: `hw_video_model=none`, `hw_rng_model=virtio` | -0.3s |
| datasource 改為 `[ConfigDrive, None]`（移除 OpenStack fallback） | -1~2s |

## 根因分析

### 並發失敗

| 假說 | 結果 |
|------|------|
| ~~Nova `max_concurrent_builds` 並發限制~~ | **排除** — 對照測試移除後仍 10/10 成功 |
| **記憶體不足（`ratio=1.0`）** | **確認** — 兩台 node ratio=1.0 下只能放 ~6 個 small VM |

### 啟動時間

| 瓶頸 | 耗時 | 可優化？ |
|------|------|---------|
| Nova spawn (BUILD→ACTIVE) | ~12s | 硬體限制 |
| Kernel boot | ~6s | 難（已是 Ubuntu minimal） |
| ~~DHCP metadata 等待~~ | ~~23s~~ | ~~**已用 config-drive 消除**~~ |
| cloud-init write_files | ~2s | 已最小化 |
| ~~不必要 services (snapd 等)~~ | ~~10-15s~~ | ~~**已停用**~~ |
| Pulumi 資源建立 | ~3s | Pulumi overhead |
| Readiness poll | ~2s | 正常 |

## 硬體容量估算

| Node | 總 RAM | Infra 佔用 | 可用（ratio=1.5） | 可放 small VM |
|------|--------|-----------|------------------|--------------|
| kolla-aio | 16GB | ~4GB | ~19GB | ~9 |
| computenode0x1 | 16GB | ~12GB | ~11GB | ~5 |
| **合計** | **32GB** | **~16GB** | **~30GB** | **~14** |

> 50 人比賽需要 50 * 2GB = 100GB RAM → 需要加 compute node 或提高 ratio

## 結論

- **單用戶 VM 題**: 啟動 **~42s**（優化前 63.5s，**-33%**），關閉 ~15s，**URL 回來即可連線**
- **並發 10**: 10/10 成功（優化前 6/10）
- **並發上限**: ratio=1.5 下約 14 個 VM（硬體 RAM 瓶頸）
- **VM 題剩餘瓶頸**: Nova spawn (~10s) + kernel+systemd (~13s) + Pulumi (~3s) = ~26s 底線，已接近硬體極限
- **進一步加速建議**: Web/API 類題目改用 `k8s-pod` scenario（啟動 <5s），VM scenario 保留給需要完整 OS 的題目（提權、kernel exploit）
- **後續行動**: 見 `TODO.md` §3.3
