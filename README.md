# Pypylon

Baslerカメラを `pypylon` で制御し、
- Speckle撮像データを保存する
- Realtime SCOS（`corrSpeckleContrast`, `BFI`, `rBFI`）を計算・表示する
ためのリポジトリです。

## セットアップ
```bash
pip install pypylon numpy pyyaml matplotlib
```

Windows環境で `python` が `WindowsApps\python.exe` を指して壊れている場合は、
`py -3 -m pip install pypylon numpy pyyaml matplotlib` を使ってください。

---

## 1) Speckle撮像（`speckle_capture/speckle_capture.py`）

### 実行
```bash
py -3 speckle_capture/speckle_capture.py \
  --config speckle_capture/capture_config.example.yaml
```
※ `python` コマンドが正常な環境では、`python ...` でも実行できます。

### プログラムの流れ
1. 設定ファイルを読み込む。
2. カメラに接続し、解像度・露光・ゲイン・トリガなどを適用する。
3. `exposure_times_us` がある場合は、カメラ内部のBasler Sequencerを循環設定する。
4. 成功したGrabResultごとに画像とChunk Timestamp / Exposure Time / Sequencer Setを対応づける。
5. 停止条件（`frame_count` または `measurement_duration_s`）まで取得し、必要に応じてチャンクを逐次保存する。
6. 保存進捗と `metadata.json` を更新し、終了状態を確定する。

### パラメータ（`capture_config.example.yaml`）

#### まず設定すべき最小項目
- `output_dir`: 保存先フォルダ
- `measurement_duration_s` **または** `frame_count`: 停止条件
- `exposure_time` または `exposure_times_us`: 露光時間（単位は µs）
- `gain`: ゲイン（露光で足りないときに調整）

#### 固定露光の例
```yaml
exposure_time: 1000.0  # 1000 µs = 1 ms
```

従来の `exposure_time` 設定はそのまま使用できます。

#### 複数露光（Sequencer）の例
```yaml
exposure_times_us:
  - 1000.0
  - 10000.0
frames_per_file: 1000
progress_interval_s: 10.0
```

`exposure_times_us` は任意長で、設定順をフレームごとにカメラ内部で循環します。上の例は
1 ms → 10 ms → 1 ms → 10 ms → … です。`exposure_time` と同時に指定した場合は
`exposure_times_us` が優先され、その旨がログに表示されます。

単一要素（例: `[1000.0]`）も許容され、Sequencerを使用しますが、撮像結果は実質的に
固定露光相当です。空配列、非数値、NaN/Inf、0以下、カメラ範囲外の値は撮像開始前に拒否されます。

複数露光にはSequencer対応カメラが必要です。非対応時や必要なGenICamノードを安全に設定できない場合は
撮像開始前にエラーとし、毎フレームのソフトウェア書き換えへはフォールバックしません。

#### 各項目の意味
- `output_dir`: 出力先ディレクトリ。
- `camera_index`: 使用カメラ番号（複数接続時）。
- `timeout_ms`: 1フレーム待機のタイムアウト。
- `frame_count`: 取得フレーム数で停止（`null`で無効）。
- `measurement_duration_s`: 取得時間で停止（`null`で無効）。
- `width`, `height`: 撮像サイズ。
- `offset_x`, `offset_y`: ROI左上オフセット。
- `pixel_format`: 画素フォーマット（例: `Mono12`）。
- `gain`: アナログ/デジタル増幅量。
- `exposure_time`: 固定露光時間（µs、従来互換）。
- `exposure_times_us`: Sequencerで循環する露光時間配列（µs）。指定時はこちらを優先。
- `black_level`: 黒レベルオフセット。
- `trigger_mode`: トリガ使用有無（`On`/`Off`）。
- `trigger_source`: トリガ入力源（例: `Line1`, `Software`）。
- `trigger_delay`: トリガから露光開始までの遅延。
- `trigger_activation`: エッジ条件（`RisingEdge` など）。
- `enable_acquisition_frame_rate`: フレームレート制御を有効化するか。
- `acquisition_frame_rate`: 目標フレームレート（fps）。
- `frames_per_file`: 1チャンクのフレーム数。長時間計測では `1000` を推奨。未指定時は従来の単一ファイル形式。
- `progress_interval_s`: 進捗ログ間隔（秒）。未指定時は10秒。

### 保存形式

`frames_per_file` 未指定時は従来互換の単一ファイルを保存します。

- `frames.npy`（`(N,H,W)`）
- `timestamps_camera_us.npy`
- `exposure_times_us.npy`
- `sequencer_set_ids.npy`

`frames_per_file` 指定時は、同じ開始・終了フレーム番号を持つチャンクを逐次保存します。

- `frames_00000000_00000999.npy`
- `timestamps_camera_us_00000000_00000999.npy`
- `exposure_times_us_00000000_00000999.npy`
- `sequencer_set_ids_00000000_00000999.npy`

各成功フレームの画像、カメラTimestamp、実適用Exposure Time、Sequencer Set IDは同じindexに保存されます。
露光条件をフレーム番号の偶奇から推定しないため、取得失敗やドロップがあっても保存画像との対応を維持します。
Chunk Exposure Timeが使えない場合だけ、Chunk Sequencer Setと登録済みSet対応から露光時間を復元します。

想定機種 `acA1440-220um` はExposure Time/Timestamp Chunkを使用できますが、Sequencer Set Active
Chunkは提供しません。この場合も実適用露光時間を正として対応を維持し、その値が登録済みSetの
1つにだけ一致するときはSet IDを逆引きします。同じ露光値を複数Setへ登録した場合など、一意に
決められないSet IDは `-1`（unknown）として保存し、フレーム番号からは推定しません。

`.npy` と `metadata.json` は一時ファイルへ書いてから正式名へ置換されます。保存途中の `.tmp` は
完成チャンクとして扱われません。チャンク書き込みキューの上限は2チャンクです。満杯時は警告して
最大5秒待ち、それでも空かなければフレームを黙って破棄せず、撮像を `failed` で終了して完成済み
チャンクを残します。

`metadata.json` にはカメラ情報、設定、`storage_format`（`single_file` / `chunked`）、
`frames_per_file`、各配列のファイル一覧、露光モードと配列、Sequencer Set数、
`capture_status`、取得/保存フレーム数、保存チャンク数、最終保存index、書き込みバイト数を記録し、
撮像開始時とチャンク保存ごとに原子的に更新します。

単一の巨大な `frames.npy` は全画像をメモリに保持するため長時間計測に不向きです。長時間撮像では
`frames_per_file: 1000` を推奨します。`progress_interval_s` ごとのログでは取得/保存数、実効fps、
ETA、バッファ/キュー使用量、保存量、ドロップ推定数を確認できます。

### 複数露光データの解釈

1 msと10 msの画像は完全な同時測定ではなく、順番に露光した別フレームです。露光条件数が増えるほど、
各露光系列の実効サンプリングレートは全体フレームレートより低下します。解析時は保存カメラTimestampを
各露光の該当indexで抽出し、露光時間ごとの系列として扱ってください。

### MATLABでの再解析

`speckle analysis/SCOSvsTime_WithNoiseSubtraction_Ver2.m` は複数露光を
`results.byExposure(k)` に分離し、各条件の `timeVec`、`rawSpeckleContrast`、
`corrSpeckleContrast`、`BFI`、`rBFI`、`meanIntensity` を独立に計算します。
固定露光と単一要素Sequencerでは、従来の5出力とMATファイルの主要フィールドも維持します。

露光時間が変わると光強度とDark/spatial noise特性も変わります。露光別Darkがない場合、同じ補正値を
複数条件へ使うことがあり、その結果には制約があります。厳密な露光間比較には露光時間ごとのDarkデータが
必要です。今回の変更にDark撮像シーケンスの自動化は含みません。

---

## 2) Realtime SCOS（`realtimeSCOS.py`）

### 実行
```bash
py -3 realtimeSCOS.py \
  --config Pypylon_realtime/realtimeSCOS_config.example.yaml
```
※ `python` コマンドが正常な環境では、`python ...` でも実行できます。

### プログラムの流れ
1. 設定ファイルを読み込む。  
2. カメラ接続・設定適用。  
3. `actual_gain_du_per_e` が `null` の場合は、camera serial/model + `nbits` + gain から自動算出。  
4. `dark_frame_count` 枚を取得して `dark_mean`, `dark_var` を作成。  
5. `spatial_frame_count` 枚を取得して空間ノイズ項（`spatial_var`）を作成。  
6. ROIを決定（`interactive_roi` か `roi_center_xy` + `roi_radius`）。  
7. 本計測フレームを取得し、各フレームで `corrSpeckleContrast` / `BFI` を計算。  
8. 時系列をリアルタイム描画し、最後に `.npy/.npz` と `metadata.json` を保存。  

### パラメータ（`realtimeSCOS_config.example.yaml`）

#### まず設定すべき最小項目
- `output_dir`: 保存先
- `frame_count`: 本計測フレーム数
- `dark_frame_count`, `spatial_frame_count`: 補正用フレーム数
- `frame_rate_hz`: 時系列軸の基準FPS
- `nbits`: 画像の有効ビット数（例: Mono12なら通常12）
- `actual_gain_du_per_e`: 量子化/ショットノイズ補正に使うゲイン係数（`null`なら自動算出）
- `camera.exposure_time`, `camera.gain`: 信号レベル調整

#### 各項目の意味
- `output_dir`: 出力先ディレクトリ。
- `frame_count`: 本計測フレーム数。
- `dark_frame_count`: ダーク統計作成用フレーム数。
- `spatial_frame_count`: 空間ノイズ統計作成用フレーム数。
- `window_size`: 局所統計（平均/分散）の計算窓サイズ。
- `show_every_n_frames`: 何フレームごとにプロット更新するか。
- `frame_rate_hz`: 時間軸生成に使うFPS。
- `nbits`: DU変換に使うビット深度。
- `actual_gain_du_per_e`: DU/e⁻ 換算係数。`null`なら camera serial/model + `nbits` + `camera.gain` から自動算出（serial校正は Matlab `GetActualGain` に合わせた gain条件分岐、条件外は modelベース計算へフォールバック）。
- `interactive_roi`: GUIクリックでROIを決めるか。
- `roi_center_xy`, `roi_radius`: 円形ROIの中心・半径。
- `camera.*`: カメラ設定（`camera_index`, `timeout_ms`, `pixel_format`, `width/height`, `exposure_time`, `gain`, `black_level`, トリガ関連, フレームレート関連）。

### 出力
- `frames_raw.npy`, `frames_corrected.npy`
- `dark_mean.npy`, `dark_var.npy`, `spatial_var.npy`
- `mask.npy`
- `scos_timeseries.npz`（`time_s`, `mean_i`, `raw_speckle_contrast`, `corr_speckle_contrast`, `bfi`, `rbfi`）
- `metadata.json`

`Pypylon_realtime/realtime_scos.py` のリアルタイム交互露光解析は今回の対象外です。将来はGrabResultの
Chunk Exposure Time / Sequencer Setを使い、露光条件別バッファへ振り分けてから解析する方針です。

---

## 設定の目安（最初の1回）
- まずは **露光時間 (`exposure_time`)** を調整して飽和しない範囲で信号を確保。
- 次に **ゲイン (`gain`)** を最小限だけ上げる。
- `frame_count` / `measurement_duration_s` は短め（例: 5〜10秒 or 数百フレーム）で確認。
- Realtime SCOSでは、`dark_frame_count` と `spatial_frame_count` を十分に確保（まずは設定例の値から開始）。
