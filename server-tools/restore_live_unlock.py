"""把 normal_live_m.default_unlocked_flag 恢复成官方原版（只有 36 个难度默认解锁）。

数据来源：抓包留存的完整主数据 zhuabao/zhuabao/tmp.db。
用法： python tools/restore_live_unlock.py [--dry-run]
"""
import argparse
import os
import shutil
import sqlite3
import time

SERVER_DB = r"d:\LLSIFLocal\honoka-chan-dev\assets\main.db"
ORIGIN_DB = r"d:\LLSIFLocal\zhuabao\zhuabao\tmp.db"


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--server-db", default=SERVER_DB)
    ap.add_argument("--origin-db", default=ORIGIN_DB)
    args = ap.parse_args()

    if not os.path.exists(args.origin_db):
        raise SystemExit("找不到原始主数据：%s" % args.origin_db)

    origin = sqlite3.connect("file:%s?mode=ro" % args.origin_db.replace("\\", "/"), uri=True)
    flags = dict(origin.execute("select live_difficulty_id, default_unlocked_flag from normal_live_m"))
    print("原始主数据：%d 条，其中默认解锁 %d 条" % (len(flags), sum(1 for v in flags.values() if v == 1)))

    if not args.dry_run:
        backup = args.server_db + ".bak" + time.strftime("%Y%m%d-%H%M%S")
        shutil.copyfile(args.server_db, backup)
        print("已备份 ->", backup)

    srv = sqlite3.connect(args.server_db)
    cur = srv.execute("select live_difficulty_id, default_unlocked_flag from normal_live_m")
    changed = 0
    for live_id, flag in cur.fetchall():
        want = flags.get(live_id)
        if want is None or want == flag:
            continue
        if not args.dry_run:
            srv.execute("update normal_live_m set default_unlocked_flag = ? where live_difficulty_id = ?",
                        (want, live_id))
        changed += 1
    if not args.dry_run:
        srv.commit()
    rows = list(srv.execute("select default_unlocked_flag, count(*) from normal_live_m group by 1"))
    print("改动 %d 条；现在的分布：%s" % (changed, rows))


if __name__ == "__main__":
    main()
