#!/usr/bin/env python3
"""
Patch ctfd-chall-manager plugin instance.py
1. 異步 Destroy：背景刪除 + flag 檔標記，Destroy 按鈕秒回
2. CREATE 等待刪除完成：防止 race condition（背景刪除把新 instance 也殺掉）
3. 防濫用：同一 instance 正在刪除中不能重複觸發 DELETE
4. INSTANCE_NOT_FOUND：回傳 200 而非 500 錯誤彈窗

用法：python3 patch_instance.py /path/to/instance.py
"""
import sys
import re

def patch(filepath):
    with open(filepath, 'r') as f:
        content = f.read()

    if 'PATCHED_ASYNC_DESTROY' in content:
        print("already patched")
        return

    # ── Patch 1: 異步 Destroy + flag 檔 + 防重複觸發 ─────────
    # DELETE handler 中的 delete_instance(challenge_id, source_id)
    # 改為：檢查 flag（防重複）→ 寫 flag → 背景 thread 刪除 → 刪完移除 flag
    old_delete = 'delete_instance(challenge_id, source_id)'
    new_delete = '''_flag = f"/tmp/ctfd_destroying_{challenge_id}_{source_id}"  # PATCHED_ASYNC_DESTROY
            import threading, os
            from flask import current_app
            # 防濫用：如果已經在刪除中，直接回傳（不重複觸發）
            if os.path.exists(_flag):
                logger.info("instance %s/%s already being destroyed, skipping", challenge_id, source_id)
            else:
                _app = current_app._get_current_object()
                open(_flag, 'w').close()
                def _bg_delete(_cid, _sid, _f, _application):
                    with _application.app_context():
                        try:
                            delete_instance(_cid, _sid)
                        except Exception as _e:
                            logger.error("async delete failed: %s", _e)
                        finally:
                            try: os.remove(_f)
                            except: pass
                threading.Thread(target=_bg_delete, args=(challenge_id, source_id, _flag, _app), daemon=True).start()'''
    content = content.replace(old_delete, new_delete, 1)  # 只替換第一個（玩家 handler）

    # ── Patch 2a: CREATE handler 等刪除完成再建 ─────────────────
    # 防止 race condition：背景刪除未完成就 create → 新 instance 被誤刪
    # 等 flag 檔消失（= 背景刪除完成），再呼叫 create_instance
    old_create = 'r = create_instance(challenge_id, source_id)'
    new_create = '''import os as _os, time as _time  # PATCHED_ASYNC_DESTROY_CREATE
            _dflag = f"/tmp/ctfd_destroying_{challenge_id}_{source_id}"
            _waited = 0
            while _os.path.exists(_dflag) and _waited < 60:
                _time.sleep(0.3)
                _waited += 0.3
            if _waited > 0:
                logger.info("CREATE waited %.1fs for destroy to complete (challenge %s)", _waited, challenge_id)
            r = create_instance(challenge_id, source_id)'''
    content = content.replace(old_create, new_create, 1)

    # ── Patch 2b: GET handler 檢查 flag 檔 ─────────────────────
    old_get = 'r = get_instance(challenge_id, source_id)'
    new_get = '''import os  # PATCHED_ASYNC_DESTROY_GET
            _flag = f"/tmp/ctfd_destroying_{challenge_id}_{source_id}"
            if os.path.exists(_flag):
                return {"success": True, "data": {}}, 200
            r = get_instance(challenge_id, source_id)'''
    content = content.replace(old_get, new_get, 1)  # 只替換第一個（玩家 GET handler）

    # ── Patch 3: INSTANCE_NOT_FOUND 回傳 200 ──────────────────
    # GET handler 的 except ChallManagerException，NOT_FOUND 改為回傳 200
    old_except = '''except ChallManagerException as e:
            logger.error("error while getting instance: {e}")
            return {
                "success": False,
                "data": {
                    "message": f"Error while communicating with CM : {e}",
                },
            }, 500'''
    new_except = '''except ChallManagerException as e:
            if "NOT_FOUND" in str(e) or "not found" in str(e).lower():
                return {"success": True, "data": {}}, 200  # PATCHED_NOTFOUND
            logger.error("error while getting instance: {e}")
            return {
                "success": False,
                "data": {
                    "message": f"Error while communicating with CM : {e}",
                },
            }, 500'''
    content = content.replace(old_except, new_except, 1)  # 只替換第一個（GET handler）

    with open(filepath, 'w') as f:
        f.write(content)
    print("patched")

if __name__ == '__main__':
    patch(sys.argv[1])
