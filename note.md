# VW_Media_Input 引き継ぎメモ

## 目的

`VW_Media_Input` は AviUtl2 用の入力プラグインとして、FFmpeg 8.1 系 DLL を使って動画/音声ファイルを読み込むための開発場所。

入力プラグインの土台として、`D:\DelphiProg\test\Syncroh2` の `Syncroh2_Input_Base.dpr` と関連ユニットをコピーして作成した。

プロジェクト名:

- `VW_Media_Input`

開発フォルダ:

- `D:\DelphiProg\test\VW_Media_Input`

## コピー元

入力プラグインの基本構造:

- `D:\DelphiProg\test\Syncroh2\Syncroh2_Input_Base.dpr`
- `D:\DelphiProg\test\Syncroh2\Syncroh2_Input_Base.dproj`
- `Plugin_Input\PluginInputBase.pas`
- `AviUtl\Input\AviUtl2InputTypes.pas`

FFmpeg 検証コード:

- `D:\DelphiProg\test\FFmpeg\04\FFmpegDecoder.pas`

FFmpeg 8.1 系 DLL:

- `avutil-60.dll`
- `avcodec-62.dll`
- `avformat-62.dll`
- `swscale-9.dll`
- `swresample-6.dll`

## 現在の状態

2026-06-02 時点:

- `VW_Media_Input.dpr` / `VW_Media_Input.dproj` を作成済み。
- `Syncroh2_Input_Base` 由来のプロジェクト名を `VW_Media_Input` に置換済み。
- `Plugin_Input\FFmpegDecoder.pas` はコピー済みだが、入力プラグイン処理にはまだ接続していない。
- Win64 Debug ビルド成功。
  - 警告 1
  - エラー 0
  - 警告は `PluginInputBase.pas` の元ベース由来。

現在のプラグイン実装は、まだ `Syncroh2_Input_Base` のダミー入力に近い。

- `PluginInputOpen` は FFmpeg で実ファイルを開いていない。
- ファイル名からサイズ、時間、fps を読む旧テスト処理が残っている。
- `PluginInputReadVideo` は実動画デコードをしていない。
- `func_read_audio` は `0` を返すだけ。
- `INPUT_PLUGIN_FLAG_AUDIO` / `INPUT_INFO_FLAG_AUDIO` はまだ使っていない。

## ビルド方法

Delphi 37.0 の環境変数を読み込んでから MSBuild で Win64 Debug をビルドする。

PowerShell から実行する場合:

```powershell
cmd.exe /s /c '"C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat" && MSBuild.exe VW_Media_Input.dproj /t:Build /p:Config=Debug /p:Platform=Win64'
```

cmd から実行する場合:

```bat
"C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat" && MSBuild.exe VW_Media_Input.dproj /t:Build /p:Config=Debug /p:Platform=Win64
```

2026-06-02 時点では、この手順で Win64 Debug ビルド成功。

- 警告 0
- エラー 0
- post-build で `C:\ProgramData\aviutl2\Plugin\VW_Media_Input` へ `.aui2` と FFmpeg DLL をコピーする。

## 現在のファイルフィルター

現状のフィルターは動画系に加えて音声系を含めている。
動画ファイルの手元サンプルが少ないため、追加分は FFmpeg に渡す仮対応として一通り入れている。

- `*.mp4`
- `*.mov`
- `*.mkv`
- `*.avi`
- `*.wmv`
- `*.asf`
- `*.webm`
- `*.mpg`
- `*.mpeg`
- `*.m2ts`
- `*.ts`
- `*.m4v`
- `*.mp3`
- `*.wav`
- `*.m4a`
- `*.aac`
- `*.wma`
- `*.flac`
- `*.ogg`
- `*.opus`

注意:

- 動画ファイルは FFmpeg 経由で映像情報、映像フレーム、音声情報を返す。
- `*.wmv` / `*.asf` / `*.webm` / `*.mpg` / `*.mpeg` / `*.m2ts` / `*.ts` / `*.m4v` はフィルター追加による仮対応で、実ファイル確認は未実施。
- `*.mp3` / `*.wav` / `*.m4a` / `*.aac` / `*.wma` / `*.flac` / `*.ogg` / `*.opus` は音声専用入力として扱い、`INPUT_INFO_FLAG_AUDIO`、`audio_format`、`audio_n`、`func_read_audio` 経路で PCM16 stereo 48kHz を返す。
- スピーカーが無いため mp3 の聴感確認は未実施だが、AviUtl2 上では問題ないように見える。

## 将来対応

まずは動画ファイル対応を優先する。

段階案:

1. `PluginInputOpen` で `TFFmpegDecoder.Open` を呼び、動画情報を取得する。
2. `PluginInputGetInfo` に幅、高さ、fps、フレーム数、画像フォーマットを設定する。
3. `PluginInputReadVideo` で指定フレームをデコードして AviUtl2 のバッファへ返す。
4. Bitmap 依存を減らし、AviUtl2 が要求する生バッファへ直接書く方向に寄せる。
5. その後、音声付き動画の `func_read_audio` 対応を検討する。

mp3 について:

- FFmpeg 経由で音声専用入力として対応済み。
- 映像ストリームが無い場合でも、音声ストリームが開ければ `TFFmpegDecoder.Open` は成功する。
- 音声のみなので `INPUT_INFO_FLAG_VIDEO` と `BITMAPINFOHEADER` は返さず、`INPUT_INFO_FLAG_AUDIO`、`audio_format`、`audio_n`、`func_read_audio` を使う。
- スピーカーが無いため聴感確認は未実施。波形/メーターなどでの確認は今後行う。

音声形式について:

- `*.wav` / `*.m4a` / `*.aac` / `*.wma` / `*.flac` / `*.ogg` / `*.opus` をフィルターへ追加済み。
- 基本的には mp3 と同じ音声専用入力経路で扱う。
- FFmpeg が開ける音声ストリームなら PCM16 stereo 48kHz として返せる可能性が高い。
- `*.wav` は AviUtl2 標準入力で扱える可能性が高いため、`VW_Media_Input.dpr` の `MEDIA_FILE_FILTER` 定数でコメント切り替えできるようにしている。
  - `MEDIA_FILE_FILTER_WITH_WAV`: wav も FFmpeg 経由で扱う。
  - `MEDIA_FILE_FILTER_WITHOUT_WAV`: wav はこのプラグインのフィルターから外し、標準入力へ任せる。
- 実ファイル確認は今後行う。

## FFmpeg 04 からの注意

`D:\DelphiProg\test\FFmpeg\04` では、FFmpeg 8.1 移行と負荷測定を実施済み。

分かったこと:

- 音声デコード負荷は小さい。
- 主な負荷は FFmpeg の映像デコード本体。
- `sws_scale + TBitmap` 変換も平均数 ms 程度の負荷がある。
- `ImagePreview` への表示コピーは大きな負荷ではなかった。

現在コピーした `Plugin_Input\FFmpegDecoder.pas` は、負荷測定のため一時的にコメントアウトされた箇所を含む可能性がある。

通常の映像表示/変換へ戻す場合は、以下を確認する。

- `Plugin_Input\FFmpegDecoder.pas` の `CopyFrameToBitmap(Frame, Bitmap)` 呼び出し
- `Unit9.pas` 側の `ImagePreview.Picture.Bitmap.Assign(Bitmap)` はこのプラグインには不要

プラグインでは `TBitmap` 表示ではなく、最終的には AviUtl2 の `buf` へ直接出力する設計を目指す。

## 現在のユニット構成

2026-06-02 時点の主なユニット構成:

### 入口

- `VW_Media_Input.dpr`
  - AviUtl2 入力プラグインの exported function を持つ。
  - `PluginInputBase.pas` の関数へ処理を委譲する。

### AviUtl2 入力プラグイン側

- `Plugin_Input\PluginInputBase.pas`
  - AviUtl2 から呼ばれる入力処理本体。
  - `PluginInputOpen` / `PluginInputGetInfo` / `PluginInputReadVideo` / `PluginInputReadAudio` を実装する。
  - 映像は `TFFmpegDecoder` へ委譲する。
  - 音声は `TPluginAudioInputReader` へ委譲する。
  - AviUtl2 へ返すフレームキャッシュ、BITMAPINFOHEADER、フレーム番号管理を持つ。

- `Plugin_Input\PluginAudioInputReader.pas`
  - AviUtl2 の `func_read_audio` 用の読み取り処理。
  - 音声用に別の `TFFmpegDecoder` を開き、PCM16 stereo 48kHz を必要分だけ順次デコードする。
  - `WAVEFORMATEX`、PCM キャッシュ、デコード済みサンプル数を管理する。

### FFmpeg デコーダ本体

- `Plugin_Input\FFmpegDecoder.pas`
  - FFmpeg デコードの中心ユニット。
  - ファイル open / close、映像デコード、音声デコード、シーク、順方向読み取りを担当する。
  - FFmpeg の低レベル API 定義、型定義、フレーム変換、統計計算は別ユニットへ分離済み。
  - 今後肥大化しやすいので、追加機能はできるだけ `Plugin_Input\FFmpeg*.pas` に逃がす方針。

### FFmpeg 周辺ユニット

- `Plugin_Input\FFmpegApi.pas`
  - FFmpeg の record / pointer 型、定数、関数ポインタ型を定義する。
  - FFmpeg DLL のロード、関数取得、`TFFmpegApi.EnsureLoaded`、`ErrorText` を持つ。
  - `RationalToDouble`、`StreamAt`、`StreamTimestampToMs` などの低レベル補助関数もここに置く。

- `Plugin_Input\FFmpegDecoderTypes.pas`
  - デコーダ公開情報と統計用の型定義。
  - `TVideoInfo`、`TAudioInfo`、`TAudioPlaybackStats`、`TDecodeLoadStats`、`TAudioWaveBuffer` を持つ。

- `Plugin_Input\FFmpegFrameConvert.pas`
  - `AVFrame` から出力バッファへの変換処理。
  - `CopyFrameToBgrx32Buffer` は AviUtl2 の 32bit BGRx バッファへ直接書き込む。
  - `CopyFrameToBitmap` は一時確認用/互換用の `TBitmap` 変換。

- `Plugin_Input\FFmpegStreamInfo.pas`
  - ストリーム情報読み取り。
  - 現在は音声ストリーム情報を `TVideoInfo.Audio` に反映する `ReadAudioInfo` を持つ。

- `Plugin_Input\FFmpegDecodeStats.pas`
  - 映像/音声の負荷統計と、PCM 音量確認用統計の計算。
  - `Plugin_Input\FFmpegDecoder.pas` 側は統計 record を持ち、このユニットの関数へ更新処理を委譲する。

### AviUtl2 型ユニット

- `AviUtl\Input\AviUtl2InputTypes.pas`
  - AviUtl2 入力プラグイン用の構造体、フラグ、関数型。

- `AviUtl2InputTypes.pas` 以外の `AviUtl` 配下ユニットと `Lib` 配下ユニットは未使用確認後に削除済み。

### 分割方針

- `Plugin_Input\FFmpegDecoder.pas` には「開く、閉じる、読む、シークする」というデコードの流れを残す。
- FFmpeg API 定義や DLL ロードは `FFmpegApi.pas` に置く。
- AviUtl2 側の都合は `PluginInputBase.pas` / `PluginAudioInputReader.pas` に寄せる。
- 変換、統計、ストリーム情報などの純粋な補助処理は `Plugin_Input\FFmpeg*.pas` へ分ける。
- 新しくまとまった責務が増えた場合は、ルートではなく `Plugin_Input` 配下へ新規ユニットを作る。

## 2026-06-02 mp3 対応状況

mp3 対応の入口を追加した。

変更内容:

- `VW_Media_Input.dpr`
  - プラグイン名を `動画/音声入力` に変更。
  - ファイルフィルターに `*.mp3` を追加。
  - 情報文言を動画/音声向けに変更。
- `Plugin_Input\FFmpegDecoder.pas`
  - 映像ストリームが無いファイルでも、音声ストリームが開ければ `Open` 成功にするよう変更。
  - mp3 のような音声専用入力では、映像デコーダを作らず音声デコーダだけを開く。
- `Plugin_Input\PluginInputBase.pas`
  - `HasVideo` を追加。
  - 音声専用ファイルでは `INPUT_INFO_FLAG_VIDEO` と `BITMAPINFOHEADER` を返さず、`INPUT_INFO_FLAG_AUDIO` / `audio_format` / `audio_n` だけ返す。
  - `PluginInputReadVideo` は映像が無い場合 `0` を返す。
  - `PluginInputReadAudio` は既存の `TPluginAudioInputReader` 経由で PCM16 stereo 48kHz を返す。

ビルド確認:

```powershell
cmd.exe /s /c '"C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat" && MSBuild.exe VW_Media_Input.dproj /t:Build /p:Config=Debug /p:Platform=Win64'
```

結果:

- Win64 Debug ビルド成功。
- 警告 0。
- エラー 0。
- post-build で `C:\ProgramData\aviutl2\Plugin\VW_Media_Input\VW_Media_Input.aui2` と FFmpeg DLL を配置済み。

動作確認メモ:

- スピーカーが無いため、実際に音が鳴るかの聴感確認は未実施。
- ただし AviUtl2 上では問題ないように見える。
- 現時点では「mp3 を音声専用入力として開き、音声情報と PCM 読み出し経路を返す」ところまで対応済みと見る。

今後確認したいこと:

- スピーカーまたは波形/メーターで、実際に音声が正しく読めているか確認する。
- 長い mp3 でシークやランダムアクセス要求が来た場合の挙動を確認する。
- 必要なら `func_read_audio` の要求位置が戻るケースに備えて、音声デコードキャッシュ/再オープン/シーク対応を強化する。

## 2026-06-02 リリース用 zip

Win64 Debug ビルド後に、AviUtl2 へ配置済みのプラグインフォルダを zip 化した。
zip 作成処理は `Setup\make_release_zip.bat` にバッチ化した。

作成元:

- `C:\ProgramData\aviutl2\Plugin\VW_Media_Input`

作成先:

- `D:\DelphiProg\test\VW_Media_Input\Setup\VW_Media_Input.zip`

GitHub Releases:

- `https://github.com/vramwiz/VW_Media_Input/releases/tag/v1.0.0`

作成コマンド:

```bat
Setup\make_release_zip.bat
```

zip 内容:

- `VW_Media_Input\VW_Media_Input.aui2`
- `VW_Media_Input\avutil-60.dll`
- `VW_Media_Input\avcodec-62.dll`
- `VW_Media_Input\avformat-62.dll`
- `VW_Media_Input\swscale-9.dll`
- `VW_Media_Input\swresample-6.dll`

メモ:

- zip は `VW_Media_Input` フォルダごと含めている。
- zip ファイル名は日付を付けず、常に `VW_Media_Input.zip` とする。
- 展開先は `C:\ProgramData\aviutl2\Plugin\VW_Media_Input` を想定する。
- zip の配置場所は `releases` ではなく `Setup` フォルダとする。
- 現時点の zip は Debug ビルド由来。正式配布時は Release ビルドで作り直すか検討する。

---

# VW_Media_Output 引き継ぎメモ

## 2026-06-03 出力プラグインへの FFmpeg 07 初期移植

`D:\DelphiProg\test\FFmpeg\07` の映像 + 音声 MP4 直接エンコード実装を、`VW_Media_Output` へ初期移植した。

追加/更新した主な内容:

- `Plugin_Output\FFmpegOutputConfig.pas`
  - 07 からコピー。
  - 現在の固定設定は Intel QSV H.264 + AAC 192 kbps。
- `Plugin_Output\FFmpegOutputEncoder.pas`
  - 07 の `FFmpegOutputTest.pas` をベースにコピー。
  - AviUtl2 から渡される `POutputInfo` を直接エンコードする `ExportOutputInfo` を追加。
  - `func_get_video` / `func_get_audio` からフレームと PCM を取り、FFmpeg DLL API で MP4 へ mux する。
- `Plugin_Input\FFmpegApi.pas`
  - 07 版へ同期。
  - 出力 mux / encode に必要な FFmpeg API 型定義と定数を含む。
- `VW_Media_Output.dpr`
  - `func_output` の placeholder を置き換え、固定設定で `ExportOutputInfo` を呼ぶようにした。
  - `func_config` は現在の固定設定を表示するだけ。
  - `func_get_config_text` は `MP4 / H.264 Intel QSV / AAC 192 kbps` を返す。
- `VW_Media_Output.dproj`
  - `Plugin_Input` / `Plugin_Output` / `AviUtl\Output` を unit search path に追加。
  - 出力エンコード関連ユニットを `DCCReference` に追加。

現在の固定設定:

- container: MP4
- video: H.264 / Intel QSV (`h264_qsv`)
- video pixel format: `nv12`
- video bitrate: `4000000`
- video preset: `veryfast`
- audio: AAC
- audio sample rate: `48000`
- audio channels: stereo / 2ch
- audio bitrate: `192000`

ビルド確認:

```powershell
cmd.exe /s /c '"C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat" && MSBuild.exe VW_Media_Output.dproj /t:Build /p:Config=Debug /p:Platform=Win64'
```

結果:

- Win64 Debug ビルド成功。
- 警告 0。
- エラー 0。
- post-build で `C:\ProgramData\aviutl2\Plugin\VW_Media_Output\VW_Media_Output.auo2` と FFmpeg DLL を配置済み。

注意:

- まだ AviUtl2 上での実出力確認は未実施。
- `func_get_video` の要求 format は 07 テスト実装由来で `1` を使っている。AviUtl2 実機で形式が合わない場合は、SDK の出力 format 値と返却バッファ形式を確認する。
- 出力設定 UI はまだ仮。固定設定を表示するだけ。
- 停止/途中失敗でも `av_write_trailer` へ到達する 07 の方針は維持している。

## 2026-06-03 AviUtl2 実行時 structured exception 修正

AviUtl2 beta45 で出力実行時に以下の structured exception が発生した。

- `table.func_output() structured exception`
- code: `0xE06D7363`
- module: `KERNELBASE.dll`

原因候補として、07 テスト実装由来の動画取得 format が本番 SDK と合っていなかった。

- 07 テスト実装:
  - `OUTPUT_TEST_FORMAT_BGRX32 = 1`
  - 自前コールバックで BGRA/BGRX 32bit を返す前提。
- AviUtl2 output2.h:
  - `func_get_video(frame, BI_RGB)`
  - `BI_RGB = 0`
  - 返る形式は RGB24bit DIB。

修正内容:

- `Plugin_Output\FFmpegOutputEncoder.pas`
  - `func_get_video` の要求 format を `0(BI_RGB)` に変更。
  - `sws_getContext` の入力 pixel format を `AV_PIX_FMT_BGRA` から `AV_PIX_FMT_BGR24` に変更。
  - 入力 stride を `w * 4` から `w * 3` に変更。
  - 音声 encoder 作成条件を `OUTPUT_INFO_FLAG_AUDIO` / `func_get_audio assigned` も見るようにした。
- `VW_Media_Output.dpr`
  - `func_output` 全体を `try..except` で囲み、Delphi 例外を AviUtl2 へ漏らさずメッセージ表示して `False` を返すようにした。
- `AviUtl\Output\AviUtl2OutputTypes.pas`
  - `output2.h` と一致する最小定義へ整理。
  - `OUTPUT_PLUGIN_TABLE` 末尾の project config 用フィールドを削除。

確認:

- Win64 Debug ビルド成功。
- 警告 0。
- エラー 0。
- post-build で `C:\ProgramData\aviutl2\Plugin\VW_Media_Output\VW_Media_Output.auo2` を更新済み。

## 2026-06-04 入力デコード高速化後の出力側課題

`VW_Media_Input` 側のデコード高速化が一区切りになったため、出力プラグイン側の性能検討の前提を更新する。

入力プラグイン側の現在状態:

- QSV decodeを優先使用。
  - 例: `decoder="h264_qsv" qsv=True`
  - QSVが使えない場合はsoftware decoderへfallback。
- AviUtl2へ返す映像形式は `YUY2`。
  - `VIDEO_OUTPUT_FORMAT = VIDEO_OUTPUT_YUY2`
- 終了時プロセス残留対策として、入力側の再利用デコーダは無効。
  - `ENABLE_REUSABLE_DECODER = False`
- I420は単体テストでは非常に速かったが、AviUtl2直接入力では受け付けられなかったため不採用。
- BGRx32はfallback/比較用として残す。

入力側の代表値:

```text
BGRx32/QSV:
next_decode elapsed avg=8.664 ms
convert     avg=7.781 ms
image_size  8294400

YUY2/QSV:
next_decode elapsed avg=3.647 ms
decode      avg=0.581 ms
transfer    avg=0.000 ms
convert     avg=2.949 ms
read_video  avg=4.306 ms
image_size  4147200
```

意味:

- 以前は入力デコード/変換が大きなボトルネックだった。
- 現在は入力側 `read_video` が約 `4.3 ms/frame` まで下がっている。
- 30fps換算の1フレーム予算は約 `33.3 ms` なので、入力取得だけならかなり軽くなった。
- そのため、今後の出力全体の遅さはエンコード側、または出力プラグイン内の変換/encode/muxが目立ちやすい。

次に必要な性能改善:

- 出力側で `get_video`、色変換、video encode、packet write、audio encode を分けて計測する。
- YUY2入力を前提に、出力エンコーダへ渡す前の変換コストを下げる。
- QSV encoder使用時でも、入力形式変換や同期待ちが残っていないか確認する。
- software x264選択時は、デコード改善後にencoder本体が主ボトルネックになりやすい。

優先して見るログ項目:

```text
get_video_ms
video_convert_ms
video_encode_write_ms
write_packet_ms
audio_encode_write_ms
total_frame_ms
```

判断:

- デコード高速化は入力側ではいったん完成。
- 次の主課題は `VW_Media_Output` 側のエンコード性能向上。
- 特に YUY2入力前提で、出力側の変換とエンコードのどちらが支配的かを再計測する。

## 2026-06-03 パフォーマンス計測ログ追加

実機確認で、`func_set_buffer_size(8, 16)` を入れても速度はほぼ変わらなかった。

観測:

- 出力速度はおおよそ 30 fps のまま。
- GPU 使用率は約 18%。
- CPU 使用率は +6% 程度。
- CPU 側は AviUtl2 のフレーム取得/デコード、または `sws_scale` の色変換で消費している可能性が高い。

次の切り分けとして、出力処理のステージ別計測ログを追加した。

追加ユニット:

- `Plugin_Output\FFmpegOutputPerfLog.pas`

切り替え:

- `FFmpegOutputPerfLog.pas`
  - `OUTPUT_PERF_LOG_ENABLED`
    - `True`: ログ出力する。
    - `False`: ログ出力しない。
  - `OUTPUT_PERF_LOG_EVERY_N_FRAMES`
    - フレーム途中経過を何フレームごとに出すか。
    - 現在は `30`。

ログ出力先:

- 出力ファイル名に `.perf.log` を付けたファイル。
- 例:
  - `sample.mp4`
  - `sample.mp4.perf.log`

計測ステージ:

- `get_video`
  - AviUtl2 の `func_get_video` 呼び出し。
- `frame_writable`
  - video frame の `av_frame_make_writable`。
- `video_convert`
  - `sws_scale` による RGB24 -> encoder pixel format 変換。
- `video_encode_write`
  - `avcodec_send_frame` / `avcodec_receive_packet` / `av_interleaved_write_frame`。
- `get_audio`
  - AviUtl2 の `func_get_audio` 呼び出し。
- `audio_writable`
  - audio frame の `av_frame_make_writable`。
- `audio_convert`
  - `swr_convert` による PCM16 -> AAC 入力形式変換。
- `audio_encode_write`
  - audio encoder send/receive/write。

ログ内容:

- 開始時:
  - 出力ファイル名
  - 解像度
  - 総フレーム数
  - encoder
  - pixel format
- 途中:
  - `OUTPUT_PERF_LOG_EVERY_N_FRAMES` ごとの frame ms / avg fps / 主要ステージ平均。
- 終了時:
  - encoded frames
  - total ms
  - avg fps
  - 各ステージの count / avg ms / max ms / total ms

確認:

- Win64 Debug ビルド成功。
- 警告 0。
- エラー 0。
- post-build で `C:\ProgramData\aviutl2\Plugin\VW_Media_Output\VW_Media_Output.auo2` を更新済み。

次の実機確認:

- AviUtl2 を再起動して出力する。
- 出力 mp4 と同じ場所に `.perf.log` が生成されることを確認する。
- `get_video` と `video_convert` と `video_encode_write` の平均/合計を見る。
  - `get_video` が大きいなら AviUtl2 側の取得/デコード待ちが主因。
  - `video_convert` が大きいなら RGB24 -> NV12 変換が主因。
  - `video_encode_write` が大きいなら QSV encoder / mux 側が主因。

次の実機確認:

- AviUtl2 を再起動して、更新後の `VW_Media_Output.auo2` で再度出力する。
- まだエラーが出る場合は、今度は `func_output` 内の `try..except` により `VW_Media_Output` のエラーメッセージが表示されるはず。
- 幅が 4 の倍数ではない動画で RGB24 DIB の行 stride が問題になる場合は、`((w * 3 + 3) and not 3)` の DIB stride 対応を追加する。

## 2026-06-03 実出力確認と次の低リスク高速化

AviUtl2 beta45 上で、出力処理が正常終了し、出力ファイルも正常であることを確認。

実測:

- おおよそ 30 fps 程度。

次に効きそうな低リスク対応として、AviUtl2 の出力コールバック周りを調整した。

変更内容:

- `Plugin_Output\FFmpegOutputEncoder.pas`
  - 出力ループ開始前に `func_set_buffer_size(8, 16)` を呼ぶようにした。
    - video buffer: `8`
    - audio buffer: `16`
    - AviUtl2 側の先読みを増やし、`func_get_video` / `func_get_audio` 待ちを少し減らす狙い。
  - RGB24 DIB の stride を `w * 3` 固定から `((w * 3 + 3) and not 3)` に変更。
    - 幅が 4 byte 境界に揃わない素材でも正しく行を読むため。
    - 既存の 1920px など 4 byte 境界に乗る素材では出力結果は変わらない。

確認:

- Win64 Debug ビルド成功。
- 警告 0。
- エラー 0。
- post-build で `C:\ProgramData\aviutl2\Plugin\VW_Media_Output\VW_Media_Output.auo2` を更新済み。

次の実機確認:

- AviUtl2 を再起動して同じ素材で再出力し、fps が変わるか確認する。
- 効果が薄い場合は、次は FFmpeg 側の色変換/encoder 入力、または CPU/GPU fallback と設定 UI を進める。

## 2026-06-03 Plugin_Input 整理

フォルダ構成を確認し、出力プラグイン本体が `Plugin_Input` に依存しているかを調べた。

確認結果:

- `VW_Media_Output.dpr` から明示参照されていた `Plugin_Input` 配下ユニットは `FFmpegApi.pas` のみ。
- `FFmpegOutputEncoder.pas` には 07 デバッグプロジェクト由来の `ExportVideoWithOutputCallbacks` と Provider クラスが残っていた。
  - これらが未使用のまま `FFmpegDecoder` / `FFmpegDecoderTypes` へ依存していた。
  - AviUtl2 出力プラグイン本体では `POutputInfo` を直接受けるため不要。

変更内容:

- `Plugin_Input\FFmpegApi.pas` を `Plugin_Output\FFmpegApi.pas` へ移動。
- `VW_Media_Output.dpr`
  - `FFmpegApi in 'Plugin_Output\FFmpegApi.pas'` に変更。
- `VW_Media_Output.dproj`
  - unit search path から `Plugin_Input` を削除。
  - `DCCReference` を `Plugin_Output\FFmpegApi.pas` に変更。
- `Plugin_Output\FFmpegOutputEncoder.pas`
  - 未使用の `ExportVideoWithOutputCallbacks` を削除。
  - 未使用の `TOutputVideoProvider` / `TOutputAudioProvider` を削除。
  - `FFmpegDecoder` / `FFmpegDecoderTypes` 依存を削除。
- `Plugin_Input` フォルダを削除。

現在の出力プラグイン側ユニット:

- `Plugin_Output\FFmpegApi.pas`
- `Plugin_Output\FFmpegOutputConfig.pas`
- `Plugin_Output\FFmpegOutputEncoder.pas`

確認:

- 現行ビルド対象の `.pas` / `.dpr` / `.dproj` から `Plugin_Input` 参照なし。
- Win64 Debug ビルド成功。
- 警告 0。
- エラー 0。
- post-build で `C:\ProgramData\aviutl2\Plugin\VW_Media_Output\VW_Media_Output.auo2` を更新済み。

## 2026-06-03 perf log 結果と YUY2 入力実験

RGB24 時のユーザー実測ログ:

- output: `C:\Users\vramw\Videos\test.mp4`
- 1920x1080 / 900 frames
- encoder: `h264_qsv`
- encoder pixel: `nv12`
- total: `40919.851 ms`
- avg fps: `21.994`

主な内訳:

- `get_video`
  - total `27343.919 ms`
  - avg `30.382 ms`
- `video_convert`
  - total `11509.611 ms`
  - avg `12.788 ms`
- `video_encode_write`
  - total `867.724 ms`
  - avg `0.963 ms`
- audio 系は全体に小さい。

見立て:

- QSV encoder / mux は主因ではない。
- 大きいのは AviUtl2 の `func_get_video` と、RGB24 から NV12 への `sws_scale`。
- 次の切り分けは、AviUtl2 から取得するフレーム形式を RGB24 ではなく YUY2 に変えて、
  `get_video` と `video_convert` の両方が下がるかを見る。

変更内容:

- `Plugin_Output\FFmpegOutputVideoInput.pas` を追加。
  - `OUTPUT_VIDEO_INPUT_KIND` で AviUtl2 への要求形式を切り替える。
  - 現在値は `ovikYuy2`。
  - RGB24 に戻す場合は `ovikRgb24` に変更する。
- `Plugin_Output\FFmpegApi.pas`
  - `AV_PIX_FMT_YUYV422 = 1` を追加。
- `Plugin_Output\FFmpegOutputEncoder.pas`
  - `func_get_video` の format 指定を `OutputVideoInputAviUtlFormat` 経由へ変更。
  - `sws_getContext` の入力 pixel format を `OutputVideoInputFFmpegPixelFormat` 経由へ変更。
  - 入力 stride を `OutputVideoInputStrideBytes` 経由へ変更。
- `Plugin_Output\FFmpegOutputPerfLog.pas`
  - ログヘッダーに `input=YUY2` / `input=BI_RGB/RGB24` を出すよう変更。

確認:

- Win64 Debug ビルド成功。
- 警告 0。
- エラー 0。
- post-build で `C:\ProgramData\aviutl2\Plugin\VW_Media_Output\VW_Media_Output.auo2` を更新済み。

次の実機確認:

- AviUtl2 を再起動して同じ素材で再出力する。
- `.perf.log` の先頭が `input=YUY2` になっていることを確認する。
- 前回ログと比較する項目:
  - `get_video avg_ms`
  - `video_convert avg_ms`
  - `finish avg_fps`

YUY2 時のユーザー実測ログ:

- output: `C:\Users\vramw\Videos\test.mp4`
- 1920x1080 / 900 frames
- encoder: `h264_qsv`
- encoder pixel: `nv12`
- input: `YUY2`
- total: `19959.969 ms`
- avg fps: `45.090`

RGB24 との比較:

- total
  - RGB24: `40919.851 ms`
  - YUY2: `19959.969 ms`
  - 約 51.2% 短縮。
- avg fps
  - RGB24: `21.994`
  - YUY2: `45.090`
  - 約 2.05 倍。
- `get_video`
  - RGB24 avg `30.382 ms`
  - YUY2 avg `18.479 ms`
  - AviUtl2 側の取得も軽くなっている。
- `video_convert`
  - RGB24 avg `12.788 ms`
  - YUY2 avg `2.516 ms`
  - 色変換は大幅に軽くなった。
- `video_encode_write`
  - RGB24 avg `0.963 ms`
  - YUY2 avg `0.488 ms`
  - encoder/mux は引き続き主因ではない。

SDK 確認:

- `D:\DelphiProg\test\Syncroh2\aviutl2_sdk\output2.h` では、出力側 `func_get_video` が要求できる形式は以下。
  - `0(BI_RGB)` = RGB24bit
  - `PA64`
  - `HF64`
  - `YUY2`
  - `YC48`
- NV12/YV12 を直接要求する経路は SDK 上は見当たらない。
- 現実的な高速候補は YUY2。PA64/HF64/YC48 はデータ量や変換負荷の面で高速化候補としては弱い。

追加実験:

- `OUTPUT_VIDEO_BUFFER_COUNT` を `8` から `16` へ変更。
  - YUY2 で速くなった状態でも `get_video` が平均 `18.479 ms` と最大要因なので、先読み量を増やして待ちが減るかを見る。
- `Plugin_Output\FFmpegOutputPerfLog.pas`
  - ログヘッダーに `buffer video=16 audio=16` を出すよう変更。

確認:

- Win64 Debug ビルド成功。
- 警告 0。
- エラー 0。
- post-build で `C:\ProgramData\aviutl2\Plugin\VW_Media_Output\VW_Media_Output.auo2` を更新済み。

次の実機確認:

- AviUtl2 を再起動して同じ素材で再出力する。
- `.perf.log` に `buffer video=16 audio=16` が出ていることを確認する。
- YUY2 / buffer=8 のログと比較する項目:
  - `get_video avg_ms`
  - `get_video max_ms`
  - `finish avg_fps`

## 2026-06-03 aviutl2_sdk_48 確認

`D:\DelphiProg\test\VW_Media_Output\aviutl2_sdk_48` に配置された最新 SDK を確認した。

出力プラグイン関連で重要な点:

- `output2.h` の `OUTPUT_INFO` は現在の実装と同じ構成。
- `func_get_video` で要求できる画像形式は以下。
  - `0(BI_RGB)` = RGB24bit
  - `PA64`
  - `HF64`
  - `YUY2`
  - `YC48`
- NV12/YV12 を直接要求する形式は追加されていない。
- `OUTPUT_PLUGIN_TABLE` は旧 SDK より末尾が拡張されている。
  - `FLAG_IMAGE = 4`
  - `FLAG_PROJECT_CONFIG = 8`
  - `func_load_project_config`
  - `func_save_project_config`

対応:

- `AviUtl\Output\AviUtl2OutputTypes.pas`
  - `OUTPUT_PLUGIN_FLAG_IMAGE` / `OUTPUT_PLUGIN_FLAG_PROJECT_CONFIG` を追加。
  - `func_load_project_config` / `func_save_project_config` を追加。
- `VW_Media_Output.dpr`
  - 現時点では project config を使わないため、追加関数ポインタは `nil` に設定。
  - `FLAG_PROJECT_CONFIG` は立てていない。

確認:

- Win64 Debug ビルド成功。
- 警告 0。
- エラー 0。
- post-build で `C:\ProgramData\aviutl2\Plugin\VW_Media_Output\VW_Media_Output.auo2` を更新済み。

## 2026-06-03 YUY2 上下反転修正

YUY2 出力で映像が上下逆になっていることを確認。

原因:

- RGB24 DIB は従来どおり bottom-up として扱い、最終行から負 stride で `sws_scale` へ渡していた。
- YUY2 でも同じ読み方をしていたため、AviUtl2 から返る YUY2 バッファの向きと合わず上下反転した。

buffer=16 / 上下反転修正前の実測:

- input: `YUY2`
- buffer: video `16` / audio `16`
- total: `21311.552 ms`
- avg fps: `42.231`
- `get_video`
  - avg `19.648 ms`
  - max `60.068 ms`
- `video_convert`
  - avg `2.794 ms`
  - max `11.795 ms`

YUY2 / buffer=8 と比べると、buffer=16 は今回の素材では速くならなかった。

- buffer=8
  - total `19959.969 ms`
  - avg fps `45.090`
  - `get_video` avg `18.479 ms`
- buffer=16
  - total `21311.552 ms`
  - avg fps `42.231`
  - `get_video` avg `19.648 ms`

修正内容:

- `Plugin_Output\FFmpegOutputVideoInput.pas`
  - `OutputVideoInputFirstLineOffset` を追加。
  - `OutputVideoInputSwsStride` を追加。
  - RGB24 は bottom-up として最終行 + 負 stride。
  - YUY2 は top-down として先頭行 + 正 stride。
- `Plugin_Output\FFmpegOutputEncoder.pas`
  - `SrcData[0]` / `SrcStride[0]` を入力形式ユニット経由で決めるよう変更。

確認:

- Win64 Debug ビルド成功。
- 警告 0。
- エラー 0。
- post-build で `C:\ProgramData\aviutl2\Plugin\VW_Media_Output\VW_Media_Output.auo2` を更新済み。

次の実機確認:

- AviUtl2 を再起動して同じ素材で再出力する。
- 映像の上下が正しくなっていることを確認する。
- 速度は buffer=16 のままなので、正常確認後に `OUTPUT_VIDEO_BUFFER_COUNT` を `8` へ戻すか判断する。

## 2026-06-03 出力設定ダイアログ追加

`D:\DelphiProg\test\FFmpeg\07\FFmpegOutputSettingsDialog.pas` の簡易ダイアログを参考に、出力プラグイン用のエンコード設定ダイアログを追加した。

追加ユニット:

- `Plugin_Output\FFmpegOutputSettingsDialog.pas`

内容:

- AviUtl2 の保存ダイアログ内の `設定` ボタンから開く。
- 保存先指定は AviUtl2 の保存ダイアログが担当するため、07 版にあった出力ファイル欄と Browse ボタンは省略。
- 設定項目:
  - encoder
    - `CPU / H.264 libx264`
    - `GPU / H.264 Intel QSV`
  - video quality
    - `High quality`
    - `Standard`
    - `Fast`
  - audio
    - `AAC 192 kbps`
    - `AAC 128 kbps`
    - `None`
- ダイアログ下部に現在選択の概要を表示する。

設定保持:

- `VW_Media_Output.dpr`
  - `CurrentSettings` を追加。
  - 初回は `InitDefaultOutputSettings` で初期化。
  - `func_config` でダイアログを開き、OK の場合だけ `CurrentSettings` を更新。
  - `func_output` では `CurrentSettings` をコピーし、保存先だけ `oip^.savefile` で上書きして出力する。
  - `func_get_config_text` は `CurrentSettings` から下部表示用の短いテキストを生成する。

その他:

- `Plugin_Output\FFmpegOutputConfig.pas`
  - 07 由来の `BGRA raw input -> ...` 表記を、現在の YUY2/RGB24 入力切り替えに合う `source input -> ...` へ変更。

確認:

- Win64 Debug ビルド成功。
- 警告 0。
- エラー 0。
- post-build で `C:\ProgramData\aviutl2\Plugin\VW_Media_Output\VW_Media_Output.auo2` を更新済み。

次の実機確認:

- AviUtl2 を再起動する。
- 保存ダイアログ右下の `設定` ボタンで、`VW Media Output Settings` が開くことを確認する。
- 設定を変更して OK した後、保存ダイアログ下部の設定テキストが更新されることを確認する。
- 出力時に選択した encoder / quality / audio が反映されることを確認する。

## 2026-06-03 設定ダイアログ表示調整と音声 bitrate 追加

設定ダイアログ下部の概要テキストがはみ出していたため、表示情報を減らした。

変更内容:

- `Plugin_Output\FFmpegOutputSettingsDialog.pas`
  - 概要表示を 3 行の詳細表示から 2 行の短い表示へ変更。
  - 例:
    - `MP4 / GPU / H.264 Intel QSV / AAC 192 kbps`
    - `Video Standard / 4.0 Mbps`
- `Plugin_Output\FFmpegOutputConfig.pas`
  - audio mode を追加。
  - 旧:
    - `AAC 192 kbps`
    - `AAC 128 kbps`
    - `None`
  - 新:
    - `AAC 576 kbps`
    - `AAC 384 kbps`
    - `AAC 256 kbps`
    - `AAC 192 kbps`
    - `AAC 128 kbps`
    - `None`

メモ:

- ニコニコ動画の投稿者向け告知で、サーバーエンコード時に生成される音声ビットレートが最大 `576 kbps` になったとの情報があるため、選択肢に `576 kbps` まで追加した。
- 既定値は従来どおり `AAC 192 kbps` のまま。

確認:

- Win64 Debug ビルド成功。
- 警告 0。
- エラー 0。
- post-build で `C:\ProgramData\aviutl2\Plugin\VW_Media_Output\VW_Media_Output.auo2` を更新済み。

## 2026-06-03 INI 設定保存追加

設定項目がまだ少ないため、保存専用 class は作らず、独自の手書き INI 保存を追加した。

追加ユニット:

- `Plugin_Output\FFmpegOutputSettingsStorage.pas`

保存場所:

- プラグイン DLL と同じフォルダ。
- 例:
  - `C:\ProgramData\aviutl2\Plugin\VW_Media_Output\VW_Media_Output.ini`

保存内容:

```ini
[Settings]
Version=1
Encoder=IntelQsv
VideoQuality=Standard
AudioMode=Aac192
```

設計方針:

- `TOutputTestSettings` 全体は保存しない。
- 保存するのは本質的な選択値だけ。
  - `Encoder`
  - `VideoQuality`
  - `AudioMode`
- 読み込み時に `InitDefaultOutputSettings` で初期化し、INI 値を `ApplyEncoderDefaults` / `ApplyVideoQuality` / `ApplyAudioMode` で展開する。
- `BitRate` / `PixelFormatName` / `Preset` などの派生値は保存しない。
- INI の `Version` は書くが、現時点では読み込み条件には使わない。
- 未知のキー、未知の値、古い値、不正値があっても例外にせず、デフォルト値へ丸める。
- INI 読み書きに失敗しても出力処理は止めない。

対応:

- `VW_Media_Output.dpr`
  - 初期化時に `LoadOutputSettingsFromIni` を呼ぶ。
  - 設定ダイアログで OK された場合だけ `SaveOutputSettingsToIni` を呼ぶ。
- `VW_Media_Output.dproj`
  - `Plugin_Output\FFmpegOutputSettingsStorage.pas` を `DCCReference` に追加。

確認:

- Win64 Debug ビルド成功。
- 警告 0。
- エラー 0。
- post-build で `C:\ProgramData\aviutl2\Plugin\VW_Media_Output\VW_Media_Output.auo2` を更新済み。

次の実機確認:

- AviUtl2 を再起動する。
- 設定ダイアログで値を変更して OK する。
- `C:\ProgramData\aviutl2\Plugin\VW_Media_Output\VW_Media_Output.ini` が作成されることを確認する。
- AviUtl2 を再起動して、前回設定が復元されることを確認する。

## 2026-06-03 FFmpegOutputEncoder の型定義分離

`Plugin_Output\FFmpegOutputEncoder.pas` が肥大化していたため、エンコード処理本体とは直接関係しない FFmpeg 公開 record / 関数型を別ユニットへ分離した。

追加ユニット:

- `Plugin_Output\FFmpegOutputApiTypes.pas`

移動した内容:

- `PAVCodecContextPublic`
- `TAVCodecContextPublic`
- `PAVFrameAudioPublic`
- `TAVFrameAudioPublic`
- `Tav_opt_set_int`
- `Tav_opt_set_sample_fmt`
- `Tav_opt_set_chlayout`

狙い:

- `FFmpegOutputEncoder.pas` の先頭にあった大きな record 群を逃がす。
- `FFmpegOutputEncoder.pas` には、映像取得、変換、encode、mux の流れを残す。
- FFmpeg の内部構造に依存する型は `FFmpegOutputApiTypes.pas` にまとめる。

対応:

- `Plugin_Output\FFmpegOutputEncoder.pas`
  - `FFmpegOutputApiTypes` を uses に追加。
  - 上記 record / function pointer 型定義を削除。
- `VW_Media_Output.dproj`
  - `Plugin_Output\FFmpegOutputApiTypes.pas` を `DCCReference` に追加。

確認:

- Win64 Debug ビルド成功。
- 警告 0。
- エラー 0。
- post-build で `C:\ProgramData\aviutl2\Plugin\VW_Media_Output\VW_Media_Output.auo2` を更新済み。

