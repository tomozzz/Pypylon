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
    framesPath = fullfile(folderPath,'frames.npy');
elseif exist(recPath,'file') == 2 && endsWith(lower(recPath),'.npy')
    framesPath = recPath;
    folderPath = fileparts(recPath);
else
    error('LoadNpyRecording:InvalidPath','Input must be a recording folder or frames.npy file.');
end

if exist(framesPath,'file') ~= 2
    error('LoadNpyRecording:MissingFrames','Missing file: %s',framesPath);
end

rawFrames = localReadNpy(framesPath);
if ndims(rawFrames) ~= 3
    error('LoadNpyRecording:BadShape','frames.npy must be a 3D array, got %dD.',ndims(rawFrames));
end

% Python capture format is (N,H,W). Convert to MATLAB (H,W,N).
rec = double(permute(rawFrames,[2 3 1]));
nOfFrames = size(rec,3);

metadataPath = fullfile(folderPath,'metadata.json');
metadata = struct();
if exist(metadataPath,'file') == 2
    metadata = jsondecode(fileread(metadataPath));
end

sourceFiles = struct();
sourceFiles.frameNames = arrayfun(@(k) sprintf('frames.npy#%d',k), (1:nOfFrames)', 'UniformOutput', false);
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

if isfield(metadata,'dtype')
    info.dtype = metadata.dtype;
end
if isfield(metadata,'shape')
    info.shape = metadata.shape;
end
info.sourceFiles = sourceFiles;

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
