unit FFmpegDecodeStats;

// FFmpegデコード処理の負荷統計と音声PCMの確認用統計を更新する補助ユニット。
// デコーダ本体が持つ統計recordの計算処理をここへ集約する。

interface

uses
  System.SysUtils, FFmpegDecoderTypes;

// 映像デコードと色変換にかかった時間の統計を更新する。
procedure UpdateVideoLoadStats(var Stats: TDecodeLoadStats; ElapsedMs: Double);
// 音声パケット処理にかかった時間の統計を更新する。
procedure UpdateAudioLoadStats(var Stats: TDecodeLoadStats; ElapsedMs: Double);
// PCMデータから音量確認用の統計を更新する。
procedure UpdateAudioPlaybackStats(var Stats: TAudioPlaybackStats; const Pcm: TBytes;
  SampleCount: Integer; PtsMs: Integer; QueuedBuffers: Integer);

implementation

uses
  System.Math;

// 映像デコードと色変換にかかった時間の統計を更新する。
procedure UpdateVideoLoadStats(var Stats: TDecodeLoadStats; ElapsedMs: Double);
begin
  Stats.VideoLastMs := ElapsedMs;
  if Stats.VideoFrames = 0 then
    Stats.VideoAverageMs := ElapsedMs
  else
    Stats.VideoAverageMs := (Stats.VideoAverageMs * 0.9) + (ElapsedMs * 0.1);
  if ElapsedMs > Stats.VideoMaxMs then
    Stats.VideoMaxMs := ElapsedMs;
  Inc(Stats.VideoFrames);
end;

// 音声パケット処理にかかった時間の統計を更新する。
procedure UpdateAudioLoadStats(var Stats: TDecodeLoadStats; ElapsedMs: Double);
begin
  Stats.AudioLastMs := ElapsedMs;
  if Stats.AudioPackets = 0 then
    Stats.AudioAverageMs := ElapsedMs
  else
    Stats.AudioAverageMs := (Stats.AudioAverageMs * 0.9) + (ElapsedMs * 0.1);
  if ElapsedMs > Stats.AudioMaxMs then
    Stats.AudioMaxMs := ElapsedMs;
  Inc(Stats.AudioPackets);
end;

// PCMデータから音量確認用の統計を更新する。
procedure UpdateAudioPlaybackStats(var Stats: TAudioPlaybackStats; const Pcm: TBytes;
  SampleCount: Integer; PtsMs: Integer; QueuedBuffers: Integer);
var
  I: Integer; // PCMサンプル走査用のインデックス
  Value: SmallInt; // 現在確認中の16bit PCM値
  AbsValue: Integer; // PCM値の絶対値
  Peak: Integer; // このPCMブロック内の最大振幅
  NonZero: Integer; // 0以外のPCM値の個数
  SumSquares: Double; // RMS計算用の二乗和
  TotalValues: Integer; // PCM値の総数
begin
  TotalValues := Length(Pcm) div SizeOf(SmallInt);
  if TotalValues <= 0 then
    Exit;

  Peak := 0;
  NonZero := 0;
  SumSquares := 0;
  for I := 0 to TotalValues - 1 do
  begin
    Value := PSmallInt(@Pcm[I * SizeOf(SmallInt)])^;
    AbsValue := Abs(Integer(Value));
    if AbsValue > Peak then
      Peak := AbsValue;
    if Value <> 0 then
      Inc(NonZero);
    SumSquares := SumSquares + Value * Value;
  end;

  Inc(Stats.DecodedFrames);
  Inc(Stats.DecodedSamples, SampleCount);
  Stats.LastPtsMs := PtsMs;
  Stats.Peak := Peak;
  Stats.Rms := Sqrt(SumSquares / TotalValues);
  Stats.NonZeroPercent := NonZero * 100.0 / TotalValues;
  Stats.QueuedBuffers := QueuedBuffers;
end;

end.
