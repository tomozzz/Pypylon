# speckle analysis (MATLAB reanalysis)

このフォルダは、Pythonで取得した `.npy` データをMATLABのSCOS解析フローで再解析するための
スクリプト群です。固定露光の旧記録と、Basler Sequencerによる複数露光記録の両方を扱います。

## 入力ファイル（計測フォルダ）

画像は次のどちらかです。

- 単一形式: `frames.npy`（Python `(N,H,W)`、MATLABでは `(H,W,N)`）
- チャンク形式: `frames_00000000_00000999.npy` など

フレーム対応メタデータも単一形式とチャンク形式の両方を読み込めます。

- `timestamps_camera_us.npy` / `timestamps_camera_us_<start>_<end>.npy`
- `exposure_times_us.npy` / `exposure_times_us_<start>_<end>.npy`
- `sequencer_set_ids.npy` / `sequencer_set_ids_<start>_<end>.npy`
- `metadata.json`

`.tmp` は未完成ファイルなので読み込み対象外です。画像と各メタデータについて、チャンク範囲、
全体フレーム範囲、配列長が一致しない場合はエラーになります。露光メタデータがない旧記録は
従来どおり固定露光として読み込めます。

## NPYローダー

- `LoadNpyRecordingMeta`: 画像本体を全読込せず、全体のファイル構造とメタデータを返す。
- `LoadNpyRecordingRange`: 1-basedの開始フレームと枚数を指定し、チャンク境界をまたいでも指定範囲だけ返す。
- `LoadNpyRecordingFrame`: 1-basedの該当1フレームと対応メタデータだけ返す。
- `LoadNpyRecording`: 従来互換の全記録読込。巨大記録にはRange/Frameを推奨。

各APIの `info` から次を参照できます。

```matlab
info.exposureTimesUs
info.sequencerSetIds
info.exposureMode
info.exposureSequenceUs
```

Metaでは全記録長、Rangeでは指定範囲、Frameでは該当フレームだけの値です。旧記録でファイルが
存在しない項目は空配列となり、エラーにはなりません。

## SCOS解析

```matlab
[timeVec, rawSpeckleContrast, corrSpeckleContrast, meanVec, info, results] = ...
    SCOSvsTime_WithNoiseSubtraction_Ver2(recName, darkName, windowSize, false, true);
```

解析フローは次のとおりです。

1. Chunk由来の実適用露光時間を許容差付きで分類する（偶数/奇数では分類しない）。
2. ROI用プレビューを1つの露光条件だけから作る。
3. Darkと空間ノイズ補正を露光条件別に準備する。
4. 画像をバッチ読込し、共通の1フレームSCOS処理へ露光別補正を渡す。
5. カメラTimestampの全体軸から各露光の該当indexだけを抽出する。
6. 露光別にraw/corrected contrast、BFI、rBFI、平均強度を保存する。

複数露光の結果は混合時系列にせず、次の構造で返します。

```matlab
results.byExposure(k).exposureTimeUs
results.byExposure(k).timeVec
results.byExposure(k).rawSpeckleContrast
results.byExposure(k).corrSpeckleContrast
results.byExposure(k).BFI
results.byExposure(k).rBFI
results.byExposure(k).meanIntensity
```

各数値配列は行がその露光条件のフレーム、列がchannelです。`frameIndices`、
`actualExposureTimesUs`、`sequencerSetIds` も保持します。浮動小数点の完全一致ではなく、
設定値間隔を越えない小さな許容差で実適用露光を対応づけます。設定sequenceに含まれていても
成功GrabResultが0枚の条件は `unusedExposureSequenceUs` に記録し、空の解析系列は作りません。

## 時間軸

複数露光では、全カメラTimestampを秒へ変換して全体先頭を0秒とした後、各露光の
`frameIndices` で抽出します。

```matlab
timeVec1ms  = allTimeVec(idx1ms);
timeVec10ms = allTimeVec(idx10ms);
```

単純な連番や「全体fps÷露光種類数」から系列時刻を作りません。カメラTimestamp自体がない
旧記録に限り、従来のフレームレート軸へフォールバックし、その全体軸から各系列を抽出します。
一部フレームだけTimestampが欠けた破損記録では、カメラ時刻と推定時刻を混在させずエラーにします。

1 msと10 msは完全な同時測定ではありません。交互に撮像するため、各露光系列の実効サンプリング
レートは全体レートより低くなります。FFTには各系列のTimestamp差から求めた実効レートを使います。

## ノイズ補正上の制約

露光時間により光強度、Dark noise、shot noise、spatial noise特性が変化します。そのため、異なる
露光時間の画像を平均してから空間補正やSCOS解析を行いません。複数露光Darkに対応条件があれば
条件別に計算します。

露光別Darkがなく、単一Darkまたは露光メタデータのない旧Darkだけがある場合は、同一補正値を
複数露光条件へ適用して警告します。この結果には制約があり、厳密な露光間比較には露光時間別の
Darkデータが必要です。今回の実装はDark撮像シーケンスの自動化を必須としていません。
補正は露光別構造体で管理し、将来の露光別Dark入力を追加できる形にしています。

## 後方互換性と出力

固定露光と単一要素Sequencerでは、従来の5出力と次のMATファイル・主要フィールドを維持します。
第6出力 `results` と同名の追加MAT変数も利用できます。

- `LocalStd*_corr.mat`
- `BFI_output.mat`
- `BFI_Ch*.mat`

実質的に複数の露光条件が観測された場合、旧出力では異露光を安全に表現できないため、旧4時系列
出力は空になり、`results.byExposure` を使用するよう警告します。MATファイルにも混合配列ではなく
`results` を保存します。

## テスト

`tests/testExposureGroupingAndTimeAxis.m` は、固定露光、単一要素Sequencer、許容差付き複数露光、
未観測sequence、ドロップ相当Timestamp、datenum変換、旧FPSフォールバック、部分Timestamp拒否を
実カメラなしで検証します。

```matlab
results = runtests(fullfile(pwd,'speckle analysis','tests'));
assertSuccess(results);
```

## ReadRecord依存の段階的削除計画

1. `SCOSvsTime_WithNoiseSubtraction_Ver2.m` の本記録入力はNPYローダーを使用する。
2. 旧Dark/TIFF/AVI互換のために残る `ReadRecord` 系利用を段階的に調査する。
3. 不要化できた後に `ReadRecord.m` を非推奨化する。
