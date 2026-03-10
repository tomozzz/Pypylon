function [rec, timeVecFile, info, sourceFiles] = LoadNpyRecording(recPath)
% LoadNpyRecording
% Loads Python-captured SCOS recording from frames.npy (+ optional timestamps/metadata)
% and returns MATLAB-friendly data:
%   rec        : [H,W,N] double
%   timeVecFile: [N,1] datenum-like timestamps when available, otherwise NaN
%   info       : SCOS-compatible info struct (metadata-first)
%   sourceFiles: helper struct with save-time metadata

if isstring(recPath)
    recPath = char(recPath);
end

if exist(recPath,'dir') == 7
    folderPath = recPath;
elseif exist(recPath,'file') == 2 && endsWith(lower(recPath),'.npy')
    folderPath = fileparts(recPath);
else
    error('LoadNpyRecording:InvalidPath','Input must be a recording folder or .npy file.');
end

metadataPath = fullfile(folderPath,'metadata.json');
metadata = struct();
if exist(metadataPath,'file') == 2
    metadata = jsondecode(fileread(metadataPath));
end

framePaths = localResolveFramePaths(recPath, folderPath, metadata);
[rawFrames, sourceFrameNames] = localReadFrameFiles(framePaths);
if ndims(rawFrames) ~= 3
    error('LoadNpyRecording:BadShape','Frame array must be 3D, got %dD.',ndims(rawFrames));
end

% Python capture format is (N,H,W). Convert to MATLAB (H,W,N).
rec = double(permute(rawFrames,[2 3 1]));
nOfFrames = size(rec,3);

sourceFiles = struct();
sourceFiles.frameNames = sourceFrameNames;
sourceFiles.startDateTime = '';

timeVecFile = nan([nOfFrames 1]);
camTsPath = fullfile(folderPath,'timestamps_camera_us.npy');
hostTsPath = fullfile(folderPath,'timestamps_host_elapsed_ms.npy');

if exist(camTsPath,'file') == 2
    camUs = double(localReadNpy(camTsPath));
    camUs = camUs(:);
    if numel(camUs) == nOfFrames
        if isfield(metadata,'capture_start_unix_s')
            tUnix = double(metadata.capture_start_unix_s) + camUs/1e6;
            dt = datetime(tUnix,'ConvertFrom','posixtime');
            timeVecFile = datenum(dt);
            sourceFiles.startDateTime = datestr(dt(1));
        else
            timeVecFile = camUs/1e6;
        end
    end
elseif exist(hostTsPath,'file') == 2
    hostMs = double(localReadNpy(hostTsPath));
    hostMs = hostMs(:);
    if numel(hostMs) == nOfFrames
        if isfield(metadata,'capture_start_unix_s')
            tUnix = double(metadata.capture_start_unix_s) + hostMs/1e3;
            dt = datetime(tUnix,'ConvertFrom','posixtime');
            timeVecFile = datenum(dt);
            sourceFiles.startDateTime = datestr(dt(1));
        else
            timeVecFile = hostMs/1e3;
        end
    end
end

if isempty(sourceFiles.startDateTime)
    sourceFiles.startDateTime = datestr(now);
end

info = struct();
info.fileType = '.npy';
info.imageSize = [size(rec,1) size(rec,2)];
info.nBits = localInferNBits(rawFrames);
info.name = GetParamsFromFileName(folderPath);

if isfield(metadata,'config')
    cfg = metadata.config;
    if isfield(cfg,'frame_rate_hz')
        info.name.FR = double(cfg.frame_rate_hz);
        info.cam.AcquisitionFrameRate = double(cfg.frame_rate_hz);
    elseif isfield(cfg,'acquisition_frame_rate')
        info.name.FR = double(cfg.acquisition_frame_rate);
        info.cam.AcquisitionFrameRate = double(cfg.acquisition_frame_rate);
    end

    if isfield(cfg,'black_level')
        info.name.BL = double(cfg.black_level);
    end
    if isfield(cfg,'gain')
        info.name.Gain = double(cfg.gain);
    end
    if isfield(cfg,'exposure_time')
        expT = double(cfg.exposure_time);
        if expT > 200 % likely microseconds from Python config
            expT = expT/1000;
        end
        info.name.expT = expT;
    end
end

% Keep camera serial/model in dedicated metadata-style fields.
if isfield(metadata,'camera_serial_number') && ~isempty(metadata.camera_serial_number)
    info.camera_serial_number = localToChar(metadata.camera_serial_number);
elseif isfield(metadata,'camera_identity') && isstruct(metadata.camera_identity) && ...
        isfield(metadata.camera_identity,'serial_number') && ~isempty(metadata.camera_identity.serial_number)
    info.camera_serial_number = localToChar(metadata.camera_identity.serial_number);
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
    if isfield(age,'gain_db') && (~isfield(info,'name') || ~isfield(info.name,'Gain') || isnan(info.name.Gain))
        info.name.Gain = double(age.gain_db);
    end
    if isfield(age,'nbits') && (~isfield(info,'nBits') || isempty(info.nBits) || isnan(info.nBits))
        info.nBits = double(age.nbits);
    end
end

if isfield(metadata,'dtype')
    info.dtype = metadata.dtype;
end
if isfield(metadata,'shape')
    info.shape = metadata.shape;
end
info.sourceFiles = sourceFiles;

end


function framePaths = localResolveFramePaths(recPath, folderPath, metadata)
if exist(recPath,'file') == 2 && endsWith(lower(recPath),'.npy')
    framePaths = {recPath};
    return;
end

framePaths = {};
if isfield(metadata,'frame_files') && ~isempty(metadata.frame_files)
    frameNames = metadata.frame_files;
    if ischar(frameNames) || isstring(frameNames)
        frameNames = cellstr(frameNames);
    end
    if iscell(frameNames)
        framePaths = cellfun(@(name) fullfile(folderPath, char(name)), frameNames, 'UniformOutput', false);
    end
end

if isempty(framePaths)
    defaultPath = fullfile(folderPath,'frames.npy');
    if exist(defaultPath,'file') == 2
        framePaths = {defaultPath};
    end
end

if isempty(framePaths)
    framePaths = localListChunkFramePaths(folderPath);
end

if isempty(framePaths)
    error('LoadNpyRecording:MissingFrames','No frame .npy files were found in %s',folderPath);
end

missing = framePaths(cellfun(@(fp) exist(fp,'file') ~= 2, framePaths));
if ~isempty(missing)
    error('LoadNpyRecording:MissingFrames','Missing frame file: %s',missing{1});
end
end

function framePaths = localListChunkFramePaths(folderPath)
chunkFiles = dir(fullfile(folderPath,'frames_*.npy'));
if isempty(chunkFiles)
    framePaths = {};
    return;
end

[~, sortIdx] = sort({chunkFiles.name});
chunkFiles = chunkFiles(sortIdx);
framePaths = arrayfun(@(f) fullfile(folderPath,f.name), chunkFiles, 'UniformOutput', false);
end

function [rawFrames, sourceFrameNames] = localReadFrameFiles(framePaths)
rawFrames = [];
sourceFrameNames = {};
for i = 1:numel(framePaths)
    chunk = localReadNpy(framePaths{i});
    if ndims(chunk) ~= 3
        error('LoadNpyRecording:BadShape','Frame file %s must be a 3D array, got %dD.',framePaths{i},ndims(chunk));
    end

    if isempty(rawFrames)
        rawFrames = chunk;
    else
        if size(chunk,2) ~= size(rawFrames,2) || size(chunk,3) ~= size(rawFrames,3)
            error('LoadNpyRecording:InconsistentShape', ...
                'Frame file %s has mismatched image size (%d,%d) vs (%d,%d).', ...
                framePaths{i},size(chunk,2),size(chunk,3),size(rawFrames,2),size(rawFrames,3));
        end
        rawFrames = cat(1, rawFrames, chunk);
    end

    [~,name,ext] = fileparts(framePaths{i});
    chunkName = [name ext];
    nChunkFrames = size(chunk,1);
    sourceFrameNames = [sourceFrameNames; arrayfun(@(k) sprintf('%s#%d',chunkName,k), (1:nChunkFrames)', 'UniformOutput', false)]; %#ok<AGROW>
end
end


function nBits = localInferNBits(rawFrames)
if isa(rawFrames,'uint8')
    nBits = 8;
elseif isa(rawFrames,'uint16')
    maxVal = double(max(rawFrames(:)));
    if maxVal <= 1023
        nBits = 10;
    elseif maxVal <= 4095
        nBits = 12;
    else
        nBits = 16;
    end
else
    maxVal = double(max(rawFrames(:)));
    if maxVal <= 255
        nBits = 8;
    elseif maxVal <= 1023
        nBits = 10;
    elseif maxVal <= 4095
        nBits = 12;
    else
        nBits = 16;
    end
end
end

function arr = localReadNpy(filePath)
try
    np = py.importlib.import_module('numpy');
    pyArr = np.load(filePath);
    arr = double(py.numpy.array(pyArr));
catch err
    error('LoadNpyRecording:ReadNpyFailed','Failed to read %s via Python numpy.load: %s',filePath,err.message);
end
end

function out = localToChar(v)
if isnumeric(v)
    out = num2str(v);
elseif isstring(v)
    out = char(v);
elseif ischar(v)
    out = v;
else
    out = char(string(v));
end
end
