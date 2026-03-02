# Pypylon

Baslerカメラを `pypylon` で制御し、Speckle撮影データを**数値配列として保存**するためのスクリプトを追加しました。

## 追加ファイル
- `speckle_capture.py`: 撮像本体
- `capture_config.example.yaml`: 一括設定用コンフィグ例

## 主な機能
- 画像を `frames.npy` (NumPy配列) で保存
- 撮像開始から各フレーム取得までの経過時間を `timestamps_ms.npy` (ms) で保存
- `metadata.json` に実行時設定と保存情報を保存
- 保存先フォルダを config または CLI `--output-dir` で指定可能
- 以下パラメータの設定対応
  - Width, Height, OffsetX, OffsetY
  - Pixel Format
  - Gain
  - Exposure Time
  - Black Level
  - Trigger Mode
  - Trigger Source
  - Trigger Delay
  - Enable Acquisition Frame Rate
  - Acquisition Frame Rate
  - Trigger Activation

## セットアップ
```bash
pip install pypylon numpy pyyaml
```

## 実行例
```bash
python speckle_capture.py --config capture_config.example.yaml
```

保存先を実行時に上書きする場合:
```bash
python speckle_capture.py --config capture_config.example.yaml --output-dir ./data/run_001
```

## 出力ファイル
- `frames.npy`: shape = `(N, H, W)`
- `timestamps_ms.npy`: shape = `(N,)`
- `metadata.json`

## 注意
- Baslerカメラ機種によって、ノード名や設定可能値が異なる場合があります。
- 設定できない項目は警告を表示してスキップします。
- `reference/` 以下の既存解析プログラムは変更していません。
