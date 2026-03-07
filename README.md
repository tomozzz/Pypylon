# Pypylon

Baslerカメラを `pypylon` で制御し、Speckle撮影データを**数値配列として保存**するためのスクリプトを追加しました。

## 追加ファイル
- `speckle_capture/speckle_capture.py`: 撮像本体
- `speckle_capture/capture_config.example.yaml`: 一括設定用コンフィグ例

## 主な機能
- 画像を `frames.npy` (NumPy配列) で保存
- Baslerカメラ内部タイムスタンプを `timestamps_camera_ticks.npy` / `timestamps_camera_us.npy` として保存
- ホスト基準の経過時間も `timestamps_host_elapsed_ms.npy` (ms) で保存
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
python speckle_capture/speckle_capture.py --config speckle_capture/capture_config.example.yaml
```

保存先を実行時に上書きする場合:
```bash
python speckle_capture/speckle_capture.py --config speckle_capture/capture_config.example.yaml --output-dir ./data/run_001
```

## 出力ファイル
- `frames.npy`: shape = `(N, H, W)`
- `timestamps_camera_ticks.npy`: shape = `(N,)`
- `timestamps_camera_us.npy`: shape = `(N,)`
- `timestamps_host_elapsed_ms.npy`: shape = `(N,)`
- `metadata.json`

## 注意
- Baslerカメラ機種によって、ノード名や設定可能値が異なる場合があります。
- 設定できない項目は警告を表示してスキップします。
- `reference/` 以下の既存解析プログラムは変更していません。


## Realtime SCOS (Matlab realtimeSCOS_Base のPython再構成)
- 追加: `realtimeSCOS.py`（エントリポイント）
- 実装本体: `Pypylon_realtime/realtime_scos.py`
- 設定例: `Pypylon_realtime/realtimeSCOS_config.example.yaml`
- Matlab処理の再分析メモ: `Pypylon_realtime/MATLAB_REANALYSIS.md`

### 機能
- Dark補正 + Spatial noise補正 + 量子化ノイズ補正を含む `corrSpeckleContrast` 計算
- `BFI = 1 / corrSpeckleContrast` と `rBFI` の算出
- リアルタイムで Speckle 指標（Kcorr^2, 平均強度, BFI）を可視化
- ピクセルデータは TIFF ではなく **数値配列** (`.npy`, `.npz`) で保存

### 実行例
```bash
python realtimeSCOS.py --config Pypylon_realtime/realtimeSCOS_config.example.yaml
```
