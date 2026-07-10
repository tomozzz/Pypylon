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

### 露光モード

露光時間の単位は、`exposure_time`と`exposure_times_us`のどちらも **µs（マイクロ秒）** です。

従来の単一露光はそのまま利用できます。

```yaml
exposure_time: 1000.0
```

カメラ内部のSequencerで1 msと10 msを交互に撮像する例です。配列は任意長で、2条件に限定されません。

```yaml
exposure_times_us:
  - 1000.0
  - 10000.0
```

- `exposure_times_us`がある場合はSequencer撮像、ない場合は`exposure_time`による固定露光です。
- 両方がある場合は`exposure_times_us`を優先し、起動時に警告します。
- 空配列、非数、0以下、カメラの`ExposureTime`範囲外の値は撮像前にエラーになります。
- 1要素の`exposure_times_us`も有効です。Sequencerは動作しますが、撮像結果は固定露光と同等です。

### Sequencer対応条件

交互露光にはBaslerのカメラ内蔵Sequencerと`SequencerSetActive` Chunkが必要です。acA1440-220umでは、USB版Sequencerの`SequencerMode`、`SequencerConfigurationMode`、`SequencerSetSelector`、`SequencerSetSave/Load`、`SequencerPathSelector`、`SequencerTriggerSource`、`SequencerSetNext`を使用します。各SetのPath 1を`FrameStart`で次のSetへ進め、最後のSetからSet 0へ戻します。

必要ノードまたは`SequencerSetActive` Chunkがないカメラでは、フレーム単位の対応を保証できないため、明確なエラーで撮像を中止します。Pythonループで`ExposureTime`を書き換える方式へはフォールバックしません。詳細は[Basler公式のace Classic/U/L USB Sequencer資料](https://docs.baslerweb.com/sequencer-%28ace-classic-u-l-usb%29)を参照してください。

### 長時間計測と逐次保存

長時間計測では次の設定を推奨します。

```yaml
frames_per_file: 1000
writer_queue_max_chunks: 2
progress_interval_s: 5.0
```

`frames_per_file: 1000`では、1000フレームごとに撮像バッファをSSD保存ワーカーへ渡し、保存後にメモリから解放します。撮像スレッドと`np.save`処理は分離され、書き込みキューは`writer_queue_max_chunks`で有界です。SSDが追いつかずキューが満杯になった場合は警告を表示して撮像側へバックプレッシャーをかけ、黙ってフレームを破棄しません。

各`.npy`は`.npy.tmp`へ書いた後に正式名へ置き換えます。1チャンク内の4ファイルのいずれかで保存に失敗した場合、その未完成チャンクだけを除去し、それ以前の完成済みチャンクは維持します。

`frames_per_file`未指定時は後方互換のため`frames.npy`を出力しますが、撮像終了まで全フレームをメモリに保持するため長時間計測には不向きです。

### 分割出力とフレーム対応

チャンク保存時は同じ開始・終了インデックスで4ファイルを保存します。

```text
frames_00000000_00000999.npy
timestamps_camera_us_00000000_00000999.npy
exposure_times_us_00000000_00000999.npy
sequencer_set_ids_00000000_00000999.npy
```

取得失敗フレームは画像・タイムスタンプ・露光時間・Set IDのいずれにも追加されないため、各配列の長さとインデックス対応は常に一致します。Sequencer撮像では、偶数・奇数ではなく各画像の`ChunkSequencerSetActive`を使用します。`ChunkExposureTime`がある場合は実測Chunk値を保存し、ない場合だけ実測Set IDから撮像前の読み戻し露光値へ対応付けます。

正常終了時は利便性のため、分割メタデータから次の全長配列も作成します。異常終了時でも分割ファイルから復元できます。

```text
timestamps_camera_us.npy
exposure_times_us.npy
sequencer_set_ids.npy
```

`metadata.json`は撮像開始時に`capture_status: in_progress`で作成され、チャンクごとに保存フレーム数、チャンク数、最終インデックス、保存量を更新します。終了状態は`completed`、ユーザー中断は`interrupted`、例外は`failed`です。

### 進捗と保存性能ログ

`progress_interval_s`ごとに、撮像済み・保存済みフレーム、経過時間、実効fps、進捗率、ETA、保存済みチャンク・容量、現在のバッファ、書き込みキュー、取得失敗数を表示します。各チャンクについてファイル名、範囲、フレーム数、データ量、保存時間、書き込み速度も表示し、終了時には成功・中断・失敗のいずれでもサマリーを表示します。

### MATLABローダーとSCOS解析

`LoadNpyRecordingMeta`、`LoadNpyRecording`、`LoadNpyRecordingRange`、`LoadNpyRecordingFrame`は新しいメタデータを任意項目として読み込みます。旧記録にファイルがなくても従来どおり動作します。

```matlab
[rec,timeVec,info,sourceFiles] = LoadNpyRecordingRange(folder,1001,500);
exposureTimesUs = info.exposureTimesUs;  % 指定範囲だけ
sequencerSetIds = info.sequencerSetIds;
exposureMode = info.exposureMode;
exposureSequenceUs = info.exposureSequenceUs;
```

`SCOSvsTime_WithNoiseSubtraction_Ver2`は保存された露光時間でフレームを分離し、各条件の元タイムスタンプを維持したまま独立に`rawSpeckleContrast`、`corrSpeckleContrast`、`BFI`、`rBFI`、`meanIntensity`を計算します。

```matlab
[timeVec,rawK,corrK,meanI,info,results] = ...
    SCOSvsTime_WithNoiseSubtraction_Ver2(recName,darkName,7,false,true);

results.byExposure(1).exposureTimeUs
results.byExposure(1).timeVec
results.byExposure(1).BFI
results.byExposure(1).rBFI
```

複数露光時は混在した従来形式の`BFI_output.mat`を作らず、`SCOS_byExposure.mat`と`BFI_output_exp_<露光時間>us.mat`を保存します。単一露光時は従来の変数名とファイル名を維持します。

1 ms系列と10 ms系列は同一瞬間の完全な同時計測ではなく、時分割の交互計測です。2条件を1回ずつ循環させる場合、各系列の実効サンプリングレートは概ね全体fpsの1/2です。一般のK条件では概ね1/Kですが、解析時間軸にはこの概算値ではなく`timestamps_camera_us`から抽出した実時刻を使用します。

### ノイズ補正上の制約

異なる露光時間の画像を混ぜて平均しません。空間ノイズ・強度フィットも露光時間ごとのフレームだけで計算します。一方、現状のAPIでは露光時間別Darkデータをまだ受け取らないため、同じDark/read-noise補正値を各露光条件へ適用します。露光時間で信号・ショットノイズ寄与が変わるため、条件間の絶対比較は慎重に解釈してください。内部結果は`results.byExposure`へ分けてあり、将来、露光別Darkデータを追加できる構造です。

`Pypylon_realtime/realtime_scos.py`のリアルタイム交互露光解析は今回未実装です。将来は同じChunk Set IDでフレームをルーティングし、露光条件ごとに独立した補正状態と描画更新周期を持たせます。

### テスト

実カメラなしのPythonテストは`pytest`不要で、標準の`unittest`から実行できます（NumPy、PyYAMLは必要です）。

```bash
python -m py_compile speckle_capture/speckle_capture.py
python -m unittest discover -s tests -v
```

MATLABとPython連携が設定済みの環境では、次を実行します。

```matlab
runtests(fullfile('speckle analysis','tests'))
```

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

---

## 設定の目安（最初の1回）
- まずは **露光時間 (`exposure_time`)** を調整して飽和しない範囲で信号を確保。
- 次に **ゲイン (`gain`)** を最小限だけ上げる。
- `frame_count` / `measurement_duration_s` は短め（例: 5〜10秒 or 数百フレーム）で確認。
- Realtime SCOSでは、`dark_frame_count` と `spatial_frame_count` を十分に確保（まずは設定例の値から開始）。
