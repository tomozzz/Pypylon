% recordFolder = '..\Records\Test1';
if ~exist('..\Records\ShaareiZedek','dir'); mkdir('..\Records\ShaareiZedek'); end
[recordFolder] = uigetdir('..\Records\ShaareiZedek');
camParams = struct();
camParams.videoFormat = 'Mono12';

% vid = videoinput("gentl",1, camParams.videoFormat);
% vid.ROIPosition = [164 188 1012 900];
% delete(vid);

camParams.TriggerMode='Off';
%% Record ReadNoise

camParams.ExposureTime = 21; % the minimum avalable
camParams.BlackLevel = 30;
camParams.Gain = 24; 
nOfFramesReadNoise = 200;
overwriteFlag = 1;
RecordFromCamera(nOfFramesReadNoise,camParams, [], recordFolder , '.tiff', 'ReadNoise_', '', overwriteFlag);

%% Record Dark Image
camParams.ExposureTime = 15000; % the minimum avalable
camParams.BlackLevel = 0;
nOfFramesDarkIm = 400;
RecordFromCamera(nOfFramesDarkIm,camParams, [], recordFolder , '.tiff', 'DarkIm_', '', overwriteFlag);

% camParams.TriggerMode='On';
% camParams.TriggerSource = 'Line4';
% rec = RecordFromCamera(0,camParams, [], '' , '.tiff', 'Trash_', '', overwriteFlag);
vid = videoinput("gentl",1, camParams.videoFormat);
triggerconfig(vid, 'hardware');
src = getselectedsource(vid);
src.TriggerSource = 'Line4';
src.TriggerMode='On';
delete(vid);

AnasthesiaTimePoints([],recordFolder)
