import argparse
import io
import re
import sys
from itertools import combinations
from pathlib import Path

import pandas as pd


def read_csv_skip_bad_lines(path: Path, only_repaired_rows: bool = False) -> pd.DataFrame:
    """distance_mにカンマが混入しているなど、列数が合わない行を警告付きでスキップして読む。

    pandasのCSVパーサーは、ヘッダーより列数が多い行が混ざっていると暗黙の
    インデックス列扱いにして全行の列がずれてしまうことがあるため、事前に
    カンマ区切り数でフィルタしてからpandasに渡す。

    only_repaired_rows=Trueのときは、命名規則に一致しない仮データファイルの中から
    "10,1"(階段前)/"10,2"(部屋前)のようなカンマ入り距離ラベルの行だけを拾い、
    それ以外の行(通常行・本当に壊れた行)は無視する。
    """
    lines = path.read_text(encoding="utf-8-sig").splitlines()
    if not lines:
        return pd.DataFrame()

    header = lines[0]
    header_fields = header.split(",")
    expected_fields = len(header_fields)
    distance_idx = [f.strip() for f in header_fields].index("distance_m")

    good_lines = [header]
    for lineno, line in enumerate(lines[1:], start=2):
        if not line.strip():
            continue
        fields = line.split(",")
        if len(fields) == expected_fields:
            if not only_repaired_rows:
                good_lines.append(line)
        elif len(fields) == expected_fields + 1:
            # distance_mに"10,1"(階段前)/"10,2"(部屋前)のようにカンマ入りの
            # ラベルが混入しているケースを、別地点の距離として"-"で結合し復元する
            merged_distance = (
                f"{fields[distance_idx].strip()}-{fields[distance_idx + 1].strip()}"
            )
            repaired = (
                fields[:distance_idx]
                + [merged_distance]
                + fields[distance_idx + 2 :]
            )
            good_lines.append(",".join(repaired))
        elif not only_repaired_rows:
            print(f"[警告] 壊れた行をスキップしました: {path}:{lineno} -> {line}", file=sys.stderr)

    if len(good_lines) <= 1:
        return pd.DataFrame()
    return pd.read_csv(io.StringIO("\n".join(good_lines)), skipinitialspace=True)


# "6-5"(rinya表記)と"5-6"(sana表記)はどちらも5階と6階の差という同じ地点を指すため統一する。
# "10-1"/"10-2"(10m地点の階段前/部屋前)のように、順序に意味がある他のN-Mラベルは
# 対象外にするため、ここでは個別の対応表として持つ(一律の昇順ソートにはしない)。
_DISTANCE_LABEL_ALIASES = {"6-5": "5-6"}


def normalize_distance_label(value: str) -> str:
    """既知の表記ゆれ(同一地点を指す別表記)のみを統一する。"""
    return _DISTANCE_LABEL_ALIASES.get(value, value)


def compute_pairwise_jaccard(df: pd.DataFrame) -> pd.DataFrame:
    """日付・距離ごとに、端末ペアそれぞれのJaccard係数を算出する。"""
    df.columns = df.columns.str.strip()
    df["timestamp"] = df["timestamp"].astype(str).str.strip()
    df["date"] = df["timestamp"].str[:10]
    df["distance_m"] = df["distance_m"].astype(str).str.strip().map(normalize_distance_label)
    df["device"] = df["device"].astype(str).str.strip()
    df["bssid"] = df["bssid"].astype(str).str.strip()

    results = []
    for (date, distance_m), group in df.groupby(["date", "distance_m"]):
        devices = group["device"].unique()
        bssid_sets = {
            d: set(group.loc[group["device"] == d, "bssid"]) for d in devices
        }

        for dev_a, dev_b in combinations(devices, 2):
            a, b = bssid_sets[dev_a], bssid_sets[dev_b]
            union = a | b
            intersection = a & b
            jaccard = len(intersection) / len(union) if union else None
            results.append(
                {
                    "date": date,
                    "distance_m": distance_m,
                    "device_a": dev_a,
                    "device_b": dev_b,
                    "intersection": len(intersection),
                    "union": len(union),
                    "jaccard": jaccard,
                }
            )

    return pd.DataFrame(results)


def average_by_distance(pairs: pd.DataFrame) -> pd.DataFrame:
    """同じ日付・距離の端末ペアのJaccard係数を平均し、距離ごとに1値へまとめる。"""
    averaged = (
        pairs.dropna(subset=["jaccard"])
        .groupby(["date", "distance_m"])["jaccard"]
        .agg(jaccard="mean", pair_count="count")
        .reset_index()
    )
    return averaged


def distance_sort_key(value: str) -> float:
    """distance_mの先頭の数値部分で昇順ソートするためのキー(例: "10-1"は10として扱う)。"""
    match = re.match(r"[-+]?\d*\.?\d+", value)
    return float(match.group()) if match else float("inf")


# 本採用のファイル名規則: 距離(mの有無・順序は問わない、階差を表す"N-M"、
# 複数距離をまとめた"N,M,..."も可)と端末名の2セグメント
# + "_wifi_measurements_<日時>.csv"
# (例: 30m_rinya_wifi_measurements_2026-07-20_17-19-01.csv
#      端末A_0_wifi_measurements_2026-07-22_12-57-29.csv
#      6-5_rinya_wifi_measurements_2026-07-20_17-24-05.csv(5階と6階の差)
#      10,20_sana_wifi_measurements_2026-07-20_17-17-42.csv(10mと20mをまとめて記録))
# それ以外の名前は仮データとして、フォルダ指定時のみ除外する
_DISTANCE_PART = r"\d+(?:\.\d+)?m?|\d+-\d+|\d+(?:,\d+)+"
VALID_FILENAME_PATTERN = re.compile(
    rf"^(?:(?:{_DISTANCE_PART})_.+|.+_(?:{_DISTANCE_PART}))"
    r"_wifi_measurements_\d{4}-\d{2}-\d{2}_\d{2}-\d{2}-\d{2}\.csv$"
)


def resolve_csv_paths(paths: list[Path]) -> list[tuple[Path, bool]]:
    """ファイルパスとフォルダパスが混在していてもCSVパスの一覧に展開する。

    戻り値は(パス, only_repaired_rows)のリスト。フォルダが渡された場合は、
    Googleドライブデスクトップの同期フォルダなど直下・サブフォルダにある*.csvのうち、
    本採用の命名規則(VALID_FILENAME_PATTERN)に一致するものは全行を対象にする。
    一致しない仮データファイルは、"10,1"/"10,2"のようなカンマ入り距離ラベルの行だけを
    拾い上げ、それ以外の行は無視する。個別にファイルを指定した場合は名前を問わず全行対象。
    """
    csv_files: list[tuple[Path, bool]] = []
    for path in paths:
        if path.is_dir():
            for csv_path in sorted(path.rglob("*.csv")):
                if VALID_FILENAME_PATTERN.match(csv_path.name):
                    csv_files.append((csv_path, False))
                else:
                    print(
                        f"[部分利用] 命名規則に一致しないため、カンマ入り距離ラベルの行のみ利用: {csv_path}",
                        file=sys.stderr,
                    )
                    csv_files.append((csv_path, True))
        else:
            csv_files.append((path, False))
    return csv_files


def main() -> None:
    parser = argparse.ArgumentParser(
        description="scannerが出力したCSVからJaccard係数を計算する"
    )
    parser.add_argument(
        "csv_files", nargs="+", type=Path,
        help="入力CSVまたはフォルダ(複数可)。フォルダを指定するとサブフォルダも含め"
        "配下の*.csvをすべて読み込む(Googleドライブデスクトップの同期フォルダを"
        "指定可能)",
    )
    parser.add_argument(
        "-o", "--output-dir", type=Path, default=Path("."),
        help="出力先ディレクトリ(日付ごとにjaccard_result_<date>.csvを書き出す)",
    )
    args = parser.parse_args()

    csv_entries = resolve_csv_paths(args.csv_files)
    if not csv_entries:
        parser.error("指定されたパスにCSVファイルが見つかりませんでした")

    frames = [
        read_csv_skip_bad_lines(f, only_repaired_rows=only_repaired)
        for f, only_repaired in csv_entries
    ]
    frames = [f for f in frames if not f.empty]
    df = pd.concat(frames, ignore_index=True)

    pairs = compute_pairwise_jaccard(df)
    averaged = average_by_distance(pairs)

    args.output_dir.mkdir(parents=True, exist_ok=True)
    for date, group in averaged.groupby("date"):
        out_path = args.output_dir / f"jaccard_result_{date}.csv"
        group = group.drop(columns="date").sort_values(
            "distance_m", key=lambda col: col.map(distance_sort_key)
        )
        group["jaccard"] = group["jaccard"].round(4)
        group.to_csv(out_path, index=False)
        print(f"書き出しました: {out_path}")


if __name__ == "__main__":
    main()