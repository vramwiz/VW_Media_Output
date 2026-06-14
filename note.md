# VW_Media_Output 開発メモ

## 2026-06-05 最終フレーム後に終了しない症状の診断ログ追加

症状:

- AviUtl2 上で最後のフレーム出力後に終了せず、ループまたは停止しているように見える。
- 環境依存の可能性もあるため、原因箇所を切り分けるためのログを追加した。

見立て:

- 映像フレーム処理自体は `for FrameIndex := 0 to oip^.n - 1` で有限ループ。
- 最後のフレーム後に止まる場合、候補は以下。
  - video encoder flush
  - video 後にまとめて実行される audio encode
  - audio encoder flush
  - `av_write_trailer`
  - FFmpeg context / codec / IO の cleanup

変更内容:

- `Plugin_Output\FFmpegOutputPerfLog.pas`
  - `TOutputPerfLogger.Trace` を追加。
  - `.perf.log` に `trace time=... ...` 形式で即時 flush される breadcrumb を出す。
- `Plugin_Output\FFmpegOutputEncoder.pas`
  - 出力開始時の `OUTPUT_INFO` 詳細を trace。
  - `avformat_alloc_output_context2`、video encoder open、audio encoder open、`avio_open`、`avformat_write_header` の通過ログを追加。
  - video loop 終了時に `video_loop_end frame_index=... encoded_frames=... aborted=... end_of_source=... fatal=...` を出す。
  - `video_flush_begin` / `video_flush_end` を追加。
  - audio encode 呼び出し前後、audio 5秒分ごとの進捗、audio read 終了、audio flush 前後を追加。
  - `av_write_trailer_begin` / `av_write_trailer_end` を追加。
  - cleanup の各解放処理前後に `cleanup_*_begin/end` を追加。

ログの読み方:

- `video_loop_end` が出ていなければ、最後の映像フレーム取得または encode 前で止まっている。
- `video_flush_begin` の後に `video_flush_end` が無ければ、video encoder flush で戻っていない。
- `audio_encode_call_begin` の後に `audio_progress` が増えているなら、最後の映像フレーム後に音声処理を続けている。
- `audio_flush_begin` の後に `audio_flush_end` が無ければ、audio encoder flush で戻っていない。
- `av_write_trailer_begin` の後に `av_write_trailer_end` が無ければ、muxer trailer 書き込みで戻っていない。
- `finish status=...` が出た後に `cleanup_*_begin` で止まっていれば、FFmpeg の解放処理で戻っていない。

確認:

- Delphi compile 本体は成功。
- post-build の `.dll` -> `.auo2` コピーは、`C:\ProgramData\aviutl2\Plugin\VW_Media_Output\VW_Media_Output.auo2` が使用中のため失敗。
- AviUtl2 を閉じてから再ビルドすると、ログ追加版が配置される。

追加対応:

- 別環境で、最終フレーム処理後に AviUtl2 の予想時間や fps が伸び続ける現象を確認。
- 音声処理が最後に走ることは想定済みだが、通常のエンコード時間を大きく超えるため永久ループと判断。
- 環境によって発生有無が分かれ、別エンコーダーでは発生しないため、HW encoder 側の flush 挙動差が濃厚。
- `SendFrameAndWritePackets` の `AVERROR_EAGAIN` 処理に進捗ガードを追加。
  - 旧実装は `avcodec_send_frame` が `EAGAIN` を返した場合、packet 回収後に無条件で `Continue` していた。
  - 環境によって `avcodec_send_frame(nil)` が `EAGAIN`、かつ `avcodec_receive_packet` も packet を返さない場合、進捗ゼロの永久ループになる可能性があった。
  - `ReceiveAndWritePacketsWithCount` を追加し、EAGAIN 後に packet が 0 個なら異常として抜けるようにした。

追加確認:

- post-build 無効の compile 確認は成功。
- 警告 0、エラー 0。

6/3 差分からの追加確認:

- `ed83048 暫定エンコード成功` から `e943a9e 音声とダイアログの修正` の間で、音声 encoder 設定が固定値ではなく `oip^.audio_rate` / `oip^.audio_ch` を反映する形へ変わっていた。
- そのため、環境やプロジェクト設定により 2ch 以外が来た場合の挙動差が出る可能性がある。
- AAC encoder 入力は `AV_SAMPLE_FMT_FLTP` の planar だが、旧コードは `OutData[0]` / `OutData[1]` だけを `swr_convert` に渡していた。
- `Settings.Audio.Channels` 分の `Frame^.data[]` を `OutData[]` に渡すよう修正した。
- これにより 1ch/2ch 以外の音声設定でも、少なくとも出力 plane 不足による不正動作を避けやすくした。

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

## 2026-06-04 出力ボトルネック確認用ログ改善

入力側の高速化により、次の主な確認対象は出力側になった。

現時点の判断:

- 既存実測では RGB24 から YUY2 への切り替えで約 `22 fps` から約 `45 fps` へ改善済み。
- `h264_qsv` の `video_encode_write` は平均 `0.5 ms/frame` 前後で、主ボトルネックではない。
- 一番大きいのは AviUtl2 からの `func_get_video` 取得時間。
- 次点は YUY2 から encoder 入力形式、主に `nv12`、への `sws_scale` 変換。
- 上下反転は問題ないことを確認済み。
- 音声と画質は未確認。

変更内容:

- `Plugin_Output\FFmpegOutputEncoder.pas`
  - `OUTPUT_VIDEO_BUFFER_COUNT` を `16` から `8` に戻した。
  - 前回実測では `buffer=16` は `buffer=8` より速くならず、むしろ少し遅かったため。
- `Plugin_Output\FFmpegOutputPerfLog.pas`
  - 最終集計に `dominant_stage=...` を追加。
  - 各 stage 行に `pct=...` を追加し、総時間に対する割合を出すようにした。

確認:

- Win64 Debug ビルド成功。
- 警告 0。
- エラー 0。
- post-build で `C:\ProgramData\aviutl2\Plugin\VW_Media_Output\VW_Media_Output.auo2` を更新済み。

次の実機確認:

- AviUtl2 を再起動して同じ素材で再出力する。
- `.perf.log` に `buffer video=8 audio=16` が出ることを確認する。
- `.perf.log` の `dominant_stage` を見る。
  - `dominant_stage=get_video` なら、AviUtl2 側のフレーム取得/入力デコード待ちが主因。
  - `dominant_stage=video_convert` なら、YUY2 -> `nv12` / `yuv420p` 変換が主因。
  - `dominant_stage=video_encode_write` なら、encoder / mux 側が主因。
- 音声確認用に、音声あり素材で `get_audio` / `audio_convert` / `audio_encode_write` の `count` と `total_ms` が出ることを確認する。
- 画質確認用に、YUY2 出力後の色、上下、音ズレ、ブロックノイズ、ビットレート設定の反映を確認する。


## 2026-06-05 main_14/59 100%到達後に非常に遅くなる件の現状

対象:

- `D:\VoiceroidProj\main_14\59`
- 主な出力先: `D:\VoiceroidProj\main_14\59\proj14_59_01_test.mp4`
- perf log: `D:\VoiceroidProj\main_14\59\proj14_59_01_test.mp4.perf.log`
- 設定例: `encoder=h264_qsv pixel=nv12 input=YUY2`
- 音声: `audio_n=2081520 audio_rate=44100 audio_ch=2`

ユーザー確認:

- デコーダーを変更しても現象は変わらない。
- エンコーダーを変更すると正常に出力されるケースがある。
- 正常なデータでは出力進捗は0%から100%まで進み、100%到達で完了する。
- 問題データでは100%到達後に停止して見える、または極端に遅くなる。

ログから確定していること:

- 映像ループ自体は最後まで到達している。
  - 例: `video_loop_end frame_index=1416 encoded_frames=1416 aborted=False fatal=False`
- QSV側の映像flushは短時間で完了している。
  - 例: `video_flush_end result=True elapsed_ms=3～5ms`
- 遅いのはFFmpegのAACエンコード処理ではない。
  - `audio_encode_write` は平均1ms未満の範囲。
- 遅い箇所はAviUtl2の `func_get_audio` 呼び出し。
  - 例: `dominant_stage=get_audio`
  - 例: `get_audio avg_ms=57.611 max_ms=1051.456 total_ms=51561.868 pct=57.9`
- 特に `sample=688128` 以降、次の音声取得で極端に戻りが遅くなる傾向がある。

試したが根本改善しなかった対策:

- 映像flush後、音声処理に入る前にvideo codec contextを解放。
  - ログには `video_codec_free_before_audio_begin/end` が出る。
  - 改善しなかったため、QSV encoder context保持だけが主因ではない。
- `func_get_audio` の取得単位を `1024` samples から `16384` samples へ拡大。
  - `get_audio` 呼び出し回数は減った。
  - しかし問題位置以降の遅さは変わらず、呼び出し回数より特定範囲の取得そのものが重いと判断。
- 音声を映像ループ中に分割投入する案も試したが、先頭付近で `fatal_after_header` になったため撤回済み。

現在残している修正:

- キャンセル時に `Result=True` のまま抜ける可能性を潰した。
- `func_get_audio` 直後にもキャンセル確認を追加。
- キャンセル時はエラーダイアログを出さないよう、abort時の最終 `ErrorMessage` は空にする。
- 映像flush後のキャンセル確認を追加。
- 調査用として、音声取得前後に以下の詳細ログを追加中。
  - `audio_read_begin sample=... length=...`
  - `audio_read_end sample=... requested=... readed=... elapsed_ms=... data_nil=...`

次に確認すること:

- 詳細ログ版を反映した状態で再出力し、最後に出ている `audio_read_begin` と対応する `audio_read_end` を見る。
- `audio_read_begin` だけ出て `audio_read_end` が出ない場合、その `sample` / `length` の `func_get_audio` が戻ってきていない。
- `audio_read_end` が出ている場合は `elapsed_ms` が大きい範囲を特定する。
- そのサンプル位置をフレーム換算する。
  - 例: `frame ~= sample * 30 / 44100`
  - `sample=688128` は約468フレーム、約15.6秒付近。

未解決:

- なぜ特定範囲の `func_get_audio` が非常に重くなるかは未確定。
- エンコーダー変更で改善する理由も未確定。ただし、現時点の計測では出力側FFmpeg AAC encodeよりもAviUtl2音声取得側の待ち時間が支配的。

## 2026-06-05 失敗データ/成功データ比較と 100% 表示の扱い

ユーザー補足:

- 画面上では 100% 到達後の問題として見えているため、ユーザー観測としては「音声処理中に遅い」というより「100% 部分で完了しない」症状。
- 正常なデータは 100% に来てすぐ完了する。
- 失敗データ:
  - `D:\VoiceroidProj\main_14\59`
  - `D:\VoiceroidProj\main_14\59\proj14_59_01_test.mp4.perf.log`
- 成功データ:
  - `D:\VoiceroidProj\Main_07\49`
  - `D:\VoiceroidProj\Main_07\49\Proj_07_49_01_nico_test.mp4.perf.log`

ログ比較:

- 失敗データも映像ループ自体は 100% 相当まで完了している。
  - `video_loop_end frame_index=1416 encoded_frames=1416 aborted=False end_of_source=False fatal=False`
  - `video_flush_end result=True elapsed_ms=4.024 fatal=False`
- 失敗データは映像完了後の後段処理で、`audio_read` が途中から急激に遅くなる。
  - `audio_encode_begin total_samples=2081520 rate=44100 ch=2`
  - `sample=770048` から `elapsed_ms=1615.887`
  - `sample=786432` で `elapsed_ms=2085.296`
  - `sample=802816` で `elapsed_ms=1842.465`
  - `sample=819200` で `elapsed_ms=1881.537`
  - その後キャンセルにより `audio_abort_requested_after_read sample=819200/2081520`
- 成功データは映像完了後、音声後段処理が短時間で完了している。
  - `video_loop_end` 18:14:47.499
  - `audio_encode_call_begin` 18:14:47.503
  - `audio_flush_end` 18:14:50.938
  - `av_write_trailer_end` 18:14:50.939
  - 約 3.4 秒で音声処理から trailer まで完了。
- 失敗データでは `audio_encode_call_begin` 19:20:22.542 からキャンセル 19:20:30.721 まで約 8.2 秒経過しても、`819200/2081520` samples までしか進んでいない。

現時点の整理:

- UI の 100% 表示は、少なくとも現在のログ上では映像ループ完了とほぼ対応している可能性が高い。
- そのため「100% に来てから完了しない」というユーザー観測は正しい。
- 一方で、ログ上で 100% 相当の映像完了後に実際に時間を消費している呼び出しは `func_get_audio`。
- ただし、ユーザー観測としては 100% 部分の問題なので、原因説明では「音声が原因」と断定せず、「100% 表示後の後段処理で `func_get_audio` が戻りにくい」と表現する。

次に見ること:

- なぜ失敗データだけ、`sample=770048` 付近以降の `func_get_audio` が 1.6～2.1 秒/回になるかを調べる。
- 成功データと失敗データで、AviUtl2 側の音声構成、オブジェクト/フィルタ、長さ、終端付近の配置差を確認する。
- 進捗表示が映像フレーム基準なら、音声後段処理中にもユーザーからは 100% 停止に見えるため、ログやキャンセル表示では「映像後処理/音声取得中」などの状態が分かるようにする案も検討する。

## 2026-06-05 音声取得を映像ループ前に先読みする修正

狙い:

- 失敗データでは UI 上 100% 到達後に完了しないように見える。
- 現行ログでは 100% 相当の `video_loop_end` 後に `func_get_audio` をまとめて呼び出しており、ここが遅いとユーザーには 100% 後の停止として見える。
- そのため、`func_get_audio` 呼び出しを映像ループ後ではなく映像ループ前に移し、100% 到達後は AviUtl2 の音声取得へ戻らない構造へ変更した。

変更内容:

- `Plugin_Output\FFmpegOutputEncoder.pas`
  - `PrefetchAudioFromCallbacks` を追加。
    - `avformat_write_header` 後、映像ループ前に `func_get_audio` から PCM16 を `TBytes` へ先読みする。
    - `.perf.log` に `audio_prefetch_*` 系ログを出す。
  - `EncodeAudioFromPcmBuffer` を追加。
    - 映像ループ後は先読み済み PCM buffer から AAC へ変換/書き込みする。
    - `audio_encode_begin ... source=prefetched` を出す。
  - 既存の AAC encode / mux の流れは維持し、AviUtl2 から音声を読むタイミングだけ前倒しした。

確認:

- Win64 Debug compile 成功。
- 警告 0、エラー 0。
- `C:\ProgramData\aviutl2\Plugin\VW_Media_Output\VW_Media_Output.auo2` へコピー成功。

次の実機確認:

- AviUtl2 を再起動して失敗データ `D:\VoiceroidProj\main_14\59` を再出力する。
- `.perf.log` の先頭付近に `audio_prefetch_call_begin` / `audio_prefetch_read_*` / `audio_prefetch_call_end` が出ることを確認する。
- 100% 到達後に `audio_read_*` が出ないことを確認する。
- もし今度は 0% 付近、または映像開始前に遅くなる場合は、`audio_prefetch_read_end elapsed_ms` が大きい sample を確認する。

## 2026-06-05 音声先読みの無音対策として映像進行同期へ変更

症状:

- 音声を映像ループ前に全量先読みすると、最初に時間はかかるが、その後は正常に終了した。
- ただし、出力音声が部分的に無音になった。

見立て:

- AviUtl2 側の音声生成/キャッシュが、映像処理開始前の全量 `func_get_audio` と相性が悪い可能性がある。
- 100% 後の待ちを避ける狙いは維持しつつ、音声取得のタイミングを映像フレーム進行に同期させる方針に変更する。

変更内容:

- `Plugin_Output\FFmpegOutputEncoder.pas`
  - 全量先読みの `PrefetchAudioFromCallbacks` をやめ、`PrefetchAudioUntilSample` に変更。
  - 映像フレームを1枚処理するごとに、そのフレーム時刻に対応する sample 位置まで PCM を先読みする。
  - 最終フレームでは `audio_n` まで先読みしてから 100% 進捗表示へ進む。
  - 映像完了後の AAC encode は、引き続き先読み済み PCM buffer から行う。
  - `audio_prefetch_chunk_stats sample=... readed=... max_abs=... silent=...` を追加。
    - まだ部分無音が出る場合、AviUtl2 から取得した時点で無音なのか、後段変換/encodeで無音化しているのかを切り分ける。

狙い:

- `func_get_audio` を 100% 後にまとめて呼ばない。
- かつ、映像処理前に音声だけ全量取得して部分無音になるリスクを避ける。
- もしまだ無音が出る場合は、`audio_prefetch_read_end` の sample 位置と出力の無音位置を対応させて調べる。

確認:

- Win64 Debug compile 成功。
- 警告 0、エラー 0。
- `C:\ProgramData\aviutl2\Plugin\VW_Media_Output\VW_Media_Output.auo2` へコピー成功。

次の作業:

- 再出力して、100% 後に待たないことと、音声の部分無音が消えることを確認する。
- まだ無音が出る場合は、無音区間に対応する `audio_prefetch_chunk_stats` の `max_abs` を見る。

## 2026-06-05 音声先読み同期後も特定話者が無音になる件

症状:

- 最初の遅さはなくなり、その後も正常に終了する。
- ただし、50% 付近から音声が部分的に無音になる。
- AviUtl2 側では琴葉茜と琴葉葵が会話しているが、葵のみ無音になるように見える。
- 最後の方では無音が元に戻る。

ログから見えたこと:

- `audio_prefetch_chunk_stats` で、問題付近に `max_abs=0 silent=True` が連続している。
- これは AAC encode 後ではなく、`func_get_audio` から返った PCM の時点で無音になっていることを示す。
- したがって、こちらの planar 変換や AAC encode で片方だけ落としているというより、音声取得タイミングにより AviUtl2 側のミックス結果が一部未反映になっている可能性が高い。

変更内容:

- `Plugin_Output\FFmpegOutputEncoder.pas`
  - `AUDIO_PREFETCH_LAG_FRAMES = 300` を追加。
  - 映像進行ぴったりで音声を読むのではなく、約 10 秒遅らせて `func_get_audio` する。
  - 最終フレームでは従来どおり `audio_n` まで読み切ってから 100% 表示へ進む。
  - ログに `audio_prefetch_mode lag_frames=300 read_chunk_samples=16384` を出す。

狙い:

- AviUtl2 側の音声合成/キャッシュが追いつく時間を置いてから音声を取得する。
- 100% 後にまとめて音声取得する構造には戻さず、ただし現在フレーム直近の音声を急いで取りに行くことも避ける。

確認:

- Win64 Debug compile 成功。
- 警告 0、エラー 0。
- `C:\ProgramData\aviutl2\Plugin\VW_Media_Output\VW_Media_Output.auo2` へコピー成功。

次の確認:

- 再出力して、50% 付近の葵無音が改善するか確認する。
- まだ無音が出る場合は、無音区間の `audio_prefetch_chunk_stats max_abs` が 0 か、0 ではないかを見る。
- 改善が足りない場合は `AUDIO_PREFETCH_LAG_FRAMES` をさらに増やす、または音声取得だけは映像完了後に戻し、進捗表示側を 100% にしない方針へ戻す。

追記:

- 無音の原因は元データ破損と判明。
- そのため、葵だけ無音になる件は出力プラグイン側の不具合ではなく正常扱い。
- 直前に入れた `AUDIO_PREFETCH_LAG_FRAMES = 300` の遅延取得方式は取り消し、ひとつ前の方式へ戻した。
  - 映像フレーム進行に同期して、そのフレーム時刻まで音声 PCM を先読みする。
  - 最終フレームでは `audio_n` まで読み切ってから 100% 表示へ進む。
  - ログは `audio_prefetch_mode frame_synced read_chunk_samples=16384`。
- Win64 Debug compile 成功、警告 0、エラー 0。
- `C:\ProgramData\aviutl2\Plugin\VW_Media_Output\VW_Media_Output.auo2` へコピー成功。

## 2026-06-14 Releaseビルドでperf logが出る問題の修正

症状:

- Releaseビルドで出力しても、出力ファイル横に `.perf.log` が生成されるように見えた。

原因:

- `Plugin_Output\FFmpegOutputPerfLog.pas` の `OUTPUT_PERF_LOG_ENABLED` が常に `True` になっていた。
- `.dproj` 側ではReleaseビルド時に `RELEASE`、Debugビルド時に `DEBUG` が定義されているが、ログ有効/無効の定数がそれを見ていなかった。

修正:

- `OUTPUT_PERF_LOG_ENABLED` を条件コンパイルに変更。
  - `DEBUG` 定義あり: `True`
  - それ以外、つまりRelease: `False`

確認:

- Win64 Release compile 成功。
- 警告 0、エラー 0。
- `C:\ProgramData\aviutl2\Plugin\VW_Media_Output\VW_Media_Output.auo2` へコピー成功。

注意:

- 既存の `.perf.log` は自動削除しない。修正後のRelease版では新規作成されない想定。
