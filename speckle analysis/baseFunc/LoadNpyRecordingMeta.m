function [timeVecFile, info, sourceFiles] = LoadNpyRecordingMeta(recPath)
% LoadNpyRecordingMeta
% Read metadata.json first, resolve frame files, and return loader metadata
% for frame-wise processing without loading the full recording tensor.

[folderPath, metadata] = localResolveFolderAndMetadata(recPath);
sourceFiles = localBuildSourceFiles(recPath, folderPath, metadata);

timeVecFile = sourceFiles.timeVecAll;
if isempty(sourceFiles.startDateTime)
    sourceFiles.startDateTime = datestr(now);
end

info = localBuildInfo(folderPath, metadata, sourceFiles);
info.sourceFiles = sourceFiles;
end

function [folderPath, metadata] = localResolveFolderAndMetadata(recPath)
if isstring(recPath), recPath = char(recPath); end
if exist(recPath,'dir') == 7
    folderPath = recPath;
elseif exist(recPath,'file') == 2 && endsWith(lower(recPath),'.npy')
    folderPath = fileparts(recPath);
else
    error('LoadNpyRecordingMeta:InvalidPath','Input must be a recording folder or .npy file.');
end

% Read metadata.json first.
metadataPath = fullfile(folderPath,'metadata.json');
metadata = struct();
if exist(metadataPath,'file') == 2
    metadata = jsondecode(fileread(metadataPath));
end
end

function sourceFiles = localBuildSourceFiles(recPath, folderPath, metadata)
framePaths = localResolveFramePaths(recPath, folderPath, metadata);
[frameCounts, imageSize] = localGetFrameCounts(framePaths);

sourceFiles = struct();
sourceFiles.framePaths = framePaths;
sourceFiles.frameCounts = frameCounts;
sourceFiles.frameEnds = cumsum(frameCounts);
sourceFiles.totalFrames = sum(frameCounts);
sourceFiles.imageSize = imageSize;
sourceFiles.frameNames = {};
sourceFiles.timeVecAll = localLoadTimeVec(folderPath, metadata, sourceFiles.totalFrames);
sourceFiles.startDateTime = '';
if ~isempty(sourceFiles.timeVecAll) && ~isnan(sourceFiles.timeVecAll(1))
    sourceFiles.startDateTime = datestr(sourceFiles.timeVecAll(1));
end
end

function info = localBuildInfo(folderPath, metadata, sourceFiles)
info = struct();
info.fileType = '.npy';
info.imageSize = sourceFiles.imageSize;

sample = localReadNpyFrame(sourceFiles.framePaths{1},1);
info.nBits = localInferNBits(sample);

warnState = warning('off','all');
info.name = struct();
try
    info.name = GetParamsFromFileName(folderPath);
catch
    info.name = struct();
end
warning(warnState);

if isfield(metadata,'config')
    cfg = metadata.config;
    if isfield(cfg,'frame_rate_hz')
        info.name.FR = double(cfg.frame_rate_hz);
        info.cam.AcquisitionFrameRate = double(cfg.frame_rate_hz);
    elseif isfield(cfg,'acquisition_frame_rate')
        info.name.FR = double(cfg.acquisition_frame_rate);
        info.cam.AcquisitionFrameRate = double(cfg.acquisition_frame_rate);
    end
    if isfield(cfg,'black_level'); info.name.BL = double(cfg.black_level); end
    if isfield(cfg,'gain'); info.name.Gain = double(cfg.gain); end
    if isfield(cfg,'exposure_time')
        expT = double(cfg.exposure_time);
        if expT > 200, expT = expT/1000; end
        info.name.expT = expT;
    end
end

% camera identification in info
if isfield(metadata,'camera_serial_number') && ~isempty(metadata.camera_serial_number)
    info.camera_serial_number = localToChar(metadata.camera_serial_number);
elseif isfield(metadata,'camera_identity') && isstruct(metadata.camera_identity) && ...
        isfield(metadata.camera_identity,'serial_number') && ~isempty(metadata.camera_identity.serial_number)
    info.camera_serial_number = localToChar(metadata.camera_identity.serial_number);
end
if isfield(info,'camera_serial_number') && ~isempty(info.camera_serial_number)
    info.cameraSN = localToChar(info.camera_serial_number);
end

if isfield(metadata,'camera_model') && ~isempty(metadata.camera_model)
    info.cameraModel = localToChar(metadata.camera_model);
elseif isfield(metadata,'camera_identity') && isstruct(metadata.camera_identity) && ...
        isfield(metadata.camera_identity,'model_name') && ~isempty(metadata.camera_identity.model_name)
    info.cameraModel = localToChar(metadata.camera_identity.model_name);
elseif isfield(metadata,'model_name') && ~isempty(metadata.model_name)
    info.cameraModel = localToChar(metadata.model_name);
end

if isfield(metadata,'actual_gain_estimation')
    age = metadata.actual_gain_estimation;
    if isfield(age,'gain_db') && (~isfield(info.name,'Gain') || isnan(info.name.Gain))
        info.name.Gain = double(age.gain_db);
    end
    if isfield(age,'nbits') && (~isfield(info,'nBits') || isempty(info.nBits) || isnan(info.nBits))
        info.nBits = double(age.nbits);
    end
end
if isfield(metadata,'dtype'); info.dtype = metadata.dtype; end
if isfield(metadata,'shape'); info.shape = metadata.shape; end
end

function [frameCounts, imageSize] = localGetFrameCounts(framePaths)
np = py.importlib.import_module('numpy');
frameCounts = zeros(numel(framePaths),1);
imageSize = [];
for i = 1:numel(framePaths)
    arr = np.load(framePaths{i}, pyargs('allow_pickle', false, 'mmap_mode', 'r'));
    shp = arr.shape;
    n = double(shp{1}); h = double(shp{2}); w = double(shp{3});
    frameCounts(i) = n;
    if isempty(imageSize)
        imageSize = [h w];
    elseif ~isequal(imageSize,[h w])
        error('LoadNpyRecordingMeta:InconsistentShape','Frame file %s has mismatched image size.',framePaths{i});
    end
end
end

function framePaths = localResolveFramePaths(recPath, folderPath, metadata)
if exist(recPath,'file') == 2 && endsWith(lower(recPath),'.npy')
    framePaths = {recPath}; return;
end
framePaths = {};
if isfield(metadata,'frame_files') && ~isempty(metadata.frame_files)
    frameNames = metadata.frame_files;
    if ischar(frameNames) || isstring(frameNames), frameNames = cellstr(frameNames); end
    if iscell(frameNames)
        framePaths = cellfun(@(name) fullfile(folderPath, char(name)), frameNames, 'UniformOutput', false);
    end
end
if isempty(framePaths)
    p = fullfile(folderPath,'frames.npy');
    if exist(p,'file') == 2, framePaths = {p}; end
end
if isempty(framePaths)
    chunkFiles = dir(fullfile(folderPath,'frames_*.npy'));
    [~,idx] = sort({chunkFiles.name}); chunkFiles = chunkFiles(idx);
    framePaths = arrayfun(@(f) fullfile(folderPath,f.name), chunkFiles, 'UniformOutput', false);
end
if isempty(framePaths)
    error('LoadNpyRecordingMeta:MissingFrames','No frame .npy files were found in %s',folderPath);
end
end

function frame = localReadNpyFrame(filePath, localIndex)
np = py.importlib.import_module('numpy');
pyArr = np.load(filePath, pyargs('allow_pickle', false, 'mmap_mode', 'r'));
pySub = np.take(pyArr, int64(localIndex-1), int32(0));
arr2d = localConvertPyArray(pySub);
frame = reshape(arr2d,[1 size(arr2d,1) size(arr2d,2)]);
end

function arr = localReadWholeNpy(filePath)
np = py.importlib.import_module('numpy');
arr = localConvertPyArray(np.load(filePath, pyargs('allow_pickle', false)));
end

function timeVecFile = localLoadTimeVec(folderPath, metadata, nOfFrames)
timeVecFile = nan([nOfFrames 1]);
camTsPath = fullfile(folderPath,'timestamps_camera_us.npy');
if exist(camTsPath,'file') == 2
    camUs = double(localReadWholeNpy(camTsPath)); camUs = camUs(:);
    if numel(camUs) == nOfFrames
        if isfield(metadata,'capture_start_unix_s')
            dt = datetime(double(metadata.capture_start_unix_s)+camUs/1e6,'ConvertFrom','posixtime');
            timeVecFile = datenum(dt);
        else
            timeVecFile = camUs/1e6;
        end
    end
end
end

function arr = localConvertPyArray(pyArr)
dtypeName = lower(char(py.str(pyArr.dtype.name)));
switch dtypeName
    case 'uint8', arr = uint8(pyArr);
    case 'uint16', arr = uint16(pyArr);
    case 'int16', arr = int16(pyArr);
    case {'single','float32'}, arr = single(pyArr);
    case {'double','float64'}, arr = double(pyArr);
    otherwise, arr = double(pyArr);
end
end

function nBits = localInferNBits(rawFrames)
maxVal = double(max(rawFrames(:)));
if maxVal <= 255, nBits = 8;
elseif maxVal <= 1023, nBits = 10;
elseif maxVal <= 4095, nBits = 12;
else, nBits = 16;
end
end

function out = localToChar(v)
if isnumeric(v), out = num2str(v);
elseif isstring(v), out = char(v);
elseif ischar(v), out = v;
else, out = char(string(v));
end
end
