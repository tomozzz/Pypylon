function [timeVecFile, info, sourceFiles] = LoadNpyRecordingMeta(recPath, startFrame, nFrames)
% LoadNpyRecordingMeta Read and validate an NPY recording manifest.
%   [TIMEVEC,INFO,SOURCEFILES] = LoadNpyRecordingMeta(RECPATH) returns
%   metadata for the complete recording without loading the image tensor.
%
%   The optional STARTFRAME/NFRAMES form is used by
%   LoadNpyRecordingRange so that per-frame metadata is read only for the
%   requested 1-based range. Existing one-argument calls retain the full
%   recording behaviour.

[folderPath, metadata, isDirectFile] = localResolveFolderAndMetadata(recPath);
sourceFiles = localBuildSourceFiles(recPath, folderPath, metadata, isDirectFile);

if nargin < 2 || isempty(startFrame)
    startFrame = 1;
end
if nargin < 3 || isempty(nFrames)
    nFrames = Inf;
end
[startFrame, nFrames] = localValidateSelection( ...
    startFrame, nFrames, sourceFiles.totalFrames);

sourceFiles.timestampSources = localResolveVectorSources( ...
    folderPath, sourceFiles, 'timestamps_camera_us');
sourceFiles.exposureSources = localResolveVectorSources( ...
    folderPath, sourceFiles, 'exposure_times_us');
sourceFiles.sequencerSetSources = localResolveVectorSources( ...
    folderPath, sourceFiles, 'sequencer_set_ids');

timestampsCameraUs = localReadVectorSelection( ...
    sourceFiles.timestampSources, startFrame, nFrames, 'camera timestamps');
exposureTimesUs = localReadVectorSelection( ...
    sourceFiles.exposureSources, startFrame, nFrames, 'exposure times');
sequencerSetIds = localReadVectorSelection( ...
    sourceFiles.sequencerSetSources, startFrame, nFrames, 'sequencer set IDs');

timestampsCameraUs = double(timestampsCameraUs(:));
exposureTimesUs = double(exposureTimesUs(:));
sequencerSetIds = double(sequencerSetIds(:));
timeVecFile = localCameraTimesToTimeVector( ...
    timestampsCameraUs, metadata, nFrames);

[exposureMode, exposureSequenceUs] = localGetExposureSettings(metadata);
sourceFiles.exposureMode = exposureMode;
sourceFiles.exposureSequenceUs = exposureSequenceUs;
info = localBuildInfo(folderPath, metadata, sourceFiles, ...
    exposureMode, exposureSequenceUs);
info.timestampsCameraUs = timestampsCameraUs;
info.exposureTimesUs = exposureTimesUs;
info.sequencerSetIds = sequencerSetIds;
info.exposureMode = exposureMode;
info.exposureSequenceUs = exposureSequenceUs;

sourceFiles.selectionStartFrame = startFrame;
sourceFiles.selectionFrameCount = nFrames;
sourceFiles.timeVecSelection = timeVecFile;
sourceFiles.timestampsCameraUsSelection = timestampsCameraUs;
sourceFiles.exposureTimesUsSelection = exposureTimesUs;
sourceFiles.sequencerSetIdsSelection = sequencerSetIds;

isFullSelection = startFrame == 1 && nFrames == sourceFiles.totalFrames;
if isFullSelection
    sourceFiles.timeVecAll = timeVecFile;
    sourceFiles.timestampsCameraUsAll = timestampsCameraUs;
    sourceFiles.exposureTimesUsAll = exposureTimesUs;
    sourceFiles.sequencerSetIdsAll = sequencerSetIds;
else
    % Do not label a range as an all-recording vector. Frame-wise loading
    % can still use the validated source descriptors above.
    sourceFiles.timeVecAll = [];
    sourceFiles.timestampsCameraUsAll = [];
    sourceFiles.exposureTimesUsAll = [];
    sourceFiles.sequencerSetIdsAll = [];
end

sourceFiles.frameNames = {};
sourceFiles.startDateTime = '';
firstFinite = find(isfinite(timeVecFile), 1, 'first');
if ~isempty(firstFinite)
    sourceFiles.startDateTime = datestr(timeVecFile(firstFinite));
else
    sourceFiles.startDateTime = datestr(now);
end
info.sourceFiles = sourceFiles;
end


function [folderPath, metadata, isDirectFile] = localResolveFolderAndMetadata(recPath)
if isstring(recPath)
    if ~isscalar(recPath)
        error('LoadNpyRecordingMeta:InvalidPath', ...
            'recPath must be a scalar string or character vector.');
    end
    recPath = char(recPath);
end
if ~ischar(recPath)
    error('LoadNpyRecordingMeta:InvalidPath', ...
        'recPath must be a scalar string or character vector.');
end

if exist(recPath, 'dir') == 7
    folderPath = recPath;
    isDirectFile = false;
elseif exist(recPath, 'file') == 2 && endsWith(lower(recPath), '.npy')
    [~, directName, directExt] = fileparts(recPath);
    if contains(lower([directName directExt]), '.tmp')
        error('LoadNpyRecordingMeta:TemporaryFile', ...
            'Temporary NPY files cannot be opened as recordings: %s', recPath);
    end
    folderPath = fileparts(recPath);
    isDirectFile = true;
else
    error('LoadNpyRecordingMeta:InvalidPath', ...
        'Input must be a recording folder or completed .npy file.');
end

metadataPath = fullfile(folderPath, 'metadata.json');
metadata = struct();
if exist(metadataPath, 'file') == 2
    metadata = jsondecode(fileread(metadataPath));
    if ~isstruct(metadata)
        error('LoadNpyRecordingMeta:BadMetadata', ...
            'metadata.json must contain a JSON object.');
    end
end
end


function sourceFiles = localBuildSourceFiles(recPath, folderPath, metadata, isDirectFile)
framePaths = localResolveFramePaths( ...
    recPath, folderPath, metadata, isDirectFile);
[frameCounts, imageSize] = localGetFrameInfo(framePaths);

[framePaths, frameCounts, storageMode, globalStartsZero, globalEndsZero] = ...
    localValidateAndOrderFrameFiles(framePaths, frameCounts, isDirectFile);

sourceFiles = struct();
sourceFiles.folderPath = folderPath;
sourceFiles.framePaths = framePaths;
sourceFiles.frameCounts = frameCounts;
sourceFiles.frameStarts = [1; cumsum(frameCounts(1:end-1)) + 1];
sourceFiles.frameEnds = cumsum(frameCounts);
sourceFiles.totalFrames = sum(frameCounts);
sourceFiles.imageSize = imageSize;
sourceFiles.storageMode = storageMode;
sourceFiles.isDirectFile = isDirectFile;
sourceFiles.frameGlobalStartsZero = globalStartsZero;
sourceFiles.frameGlobalEndsZero = globalEndsZero;

if sourceFiles.totalFrames < 1
    error('LoadNpyRecordingMeta:NoFrames', ...
        'The recording contains no frames.');
end
end


function framePaths = localResolveFramePaths(recPath, folderPath, metadata, isDirectFile)
if isDirectFile
    framePaths = {char(recPath)};
    return;
end

framePaths = {};
if isfield(metadata, 'frame_files') && ~isempty(metadata.frame_files)
    frameNames = localTextList(metadata.frame_files, 'metadata.frame_files');
    completedNames = {};
    for i = 1:numel(frameNames)
        name = frameNames{i};
        if contains(lower(name), '.tmp')
            continue;
        end
        parsedName = localParseChunkName(name, 'frames');
        if ~(strcmp(name, 'frames.npy') || parsedName.matched)
            error('LoadNpyRecordingMeta:BadFrameFileName', ...
                'Unsupported frame file listed in metadata.json: %s', name);
        end
        completedNames{end+1,1} = name; %#ok<AGROW>
    end
    if ~isempty(completedNames)
        framePaths = cellfun(@(name) fullfile(folderPath, name), ...
            completedNames, 'UniformOutput', false);
        missing = framePaths(cellfun(@(path) exist(path, 'file') ~= 2, framePaths));
        if ~isempty(missing)
            error('LoadNpyRecordingMeta:MissingFrames', ...
                'Frame file listed in metadata.json is missing: %s', missing{1});
        end

        % metadata.json is updated after each atomic chunk rename. If the
        % process stops between those operations, a completed chunk can be
        % newer than frame_files. Strictly enumerate the directory so that
        % such durable chunks remain readable; temporary files stay ignored.
        isChunkManifest = all(cellfun(@(name) ...
            localIsChunkName(name, 'frames'), completedNames));
        if isChunkManifest
            [diskChunkPaths, ~, ~] = localListChunkFiles(folderPath, 'frames');
            if ~isempty(diskChunkPaths)
                framePaths = diskChunkPaths;
            end
        end
    end
end

if isempty(framePaths)
    singlePath = fullfile(folderPath, 'frames.npy');
    if exist(singlePath, 'file') == 2
        framePaths = {singlePath};
    end
end

if isempty(framePaths)
    [framePaths, ~, ~] = localListChunkFiles(folderPath, 'frames');
end

if isempty(framePaths)
    error('LoadNpyRecordingMeta:MissingFrames', ...
        'No completed frame .npy files were found in %s', folderPath);
end
end


function [frameCounts, imageSize] = localGetFrameInfo(framePaths)
np = py.importlib.import_module('numpy');
frameCounts = zeros(numel(framePaths), 1);
imageSize = [];
for i = 1:numel(framePaths)
    pyArr = np.load(framePaths{i}, ...
        pyargs('allow_pickle', false, 'mmap_mode', 'r'));
    if double(pyArr.ndim) ~= 3
        error('LoadNpyRecordingMeta:BadShape', ...
            'Frame file %s must have shape (N,H,W).', framePaths{i});
    end
    shp = pyArr.shape;
    n = double(shp{1});
    h = double(shp{2});
    w = double(shp{3});
    if n < 1 || h < 1 || w < 1
        error('LoadNpyRecordingMeta:BadShape', ...
            'Frame file %s has an empty dimension.', framePaths{i});
    end
    frameCounts(i) = n;
    if isempty(imageSize)
        imageSize = [h w];
    elseif ~isequal(imageSize, [h w])
        error('LoadNpyRecordingMeta:InconsistentShape', ...
            'Frame file %s has image size [%d %d], expected [%d %d].', ...
            framePaths{i}, h, w, imageSize(1), imageSize(2));
    end
end
end


function [paths, counts, storageMode, globalStartsZero, globalEndsZero] = ...
        localValidateAndOrderFrameFiles(paths, counts, isDirectFile)
nFiles = numel(paths);
chunkInfo = repmat(struct('matched', false, 'startZero', NaN, ...
    'endZero', NaN), nFiles, 1);
isSingleName = false(nFiles, 1);
for i = 1:nFiles
    [~, name, ext] = fileparts(paths{i});
    fileName = [name ext];
    isSingleName(i) = strcmp(fileName, 'frames.npy');
    chunkInfo(i) = localParseChunkName(fileName, 'frames');
end

if isDirectFile
    if nFiles ~= 1
        error('LoadNpyRecordingMeta:Internal', ...
            'A direct NPY path must resolve to one frame file.');
    end
    if chunkInfo(1).matched
        expectedCount = chunkInfo(1).endZero - chunkInfo(1).startZero + 1;
        if counts(1) ~= expectedCount
            error('LoadNpyRecordingMeta:FrameRangeMismatch', ...
                'Frame file range encodes %d frames but contains %d: %s', ...
                expectedCount, counts(1), paths{1});
        end
        storageMode = 'chunked';
        globalStartsZero = chunkInfo(1).startZero;
        globalEndsZero = chunkInfo(1).endZero;
    else
        storageMode = 'single';
        globalStartsZero = 0;
        globalEndsZero = counts(1) - 1;
    end
    return;
end

if nFiles == 1 && isSingleName(1)
    storageMode = 'single';
    globalStartsZero = 0;
    globalEndsZero = counts(1) - 1;
    return;
end

if any(isSingleName) || ~all([chunkInfo.matched])
    error('LoadNpyRecordingMeta:BadFrameFileSet', ...
        'A recording must use frames.npy or strictly named frames_<start>_<end>.npy chunks.');
end

starts = [chunkInfo.startZero]';
ends = [chunkInfo.endZero]';
[starts, order] = sort(starts);
ends = ends(order);
paths = paths(order);
counts = counts(order);

expectedStart = 0;
for i = 1:nFiles
    if starts(i) ~= expectedStart
        error('LoadNpyRecordingMeta:NonContiguousFrames', ...
            'Frame chunks have a gap or overlap before %s; expected start %d, got %d.', ...
            paths{i}, expectedStart, starts(i));
    end
    encodedCount = ends(i) - starts(i) + 1;
    if ends(i) < starts(i) || counts(i) ~= encodedCount
        error('LoadNpyRecordingMeta:FrameRangeMismatch', ...
            'Frame chunk %s encodes %d frames but contains %d.', ...
            paths{i}, encodedCount, counts(i));
    end
    expectedStart = ends(i) + 1;
end

storageMode = 'chunked';
globalStartsZero = starts;
globalEndsZero = ends;
end


function [startFrame, nFrames] = localValidateSelection(startFrame, nFrames, totalFrames)
if ~(isnumeric(startFrame) && isscalar(startFrame) && ...
        isfinite(startFrame) && startFrame == fix(startFrame) && startFrame >= 1)
    error('LoadNpyRecordingMeta:Range', ...
        'startFrame must be a finite positive integer.');
end
startFrame = double(startFrame);
if startFrame > totalFrames
    error('LoadNpyRecordingMeta:Range', ...
        'startFrame must be in [1,%d], got %d.', totalFrames, startFrame);
end

if ~(isnumeric(nFrames) && isscalar(nFrames))
    error('LoadNpyRecordingMeta:Range', ...
        'nFrames must be a positive integer or Inf.');
end
if isinf(nFrames) && nFrames > 0
    nFrames = totalFrames - startFrame + 1;
elseif ~(isfinite(nFrames) && nFrames == fix(nFrames) && nFrames >= 1)
    error('LoadNpyRecordingMeta:Range', ...
        'nFrames must be a positive integer or Inf.');
else
    nFrames = min(double(nFrames), totalFrames - startFrame + 1);
end
end


function sources = localResolveVectorSources(folderPath, sourceFiles, prefix)
sources = localEmptySources();
singlePath = fullfile(folderPath, [prefix '.npy']);
hasSingle = exist(singlePath, 'file') == 2;
[chunkPaths, chunkStarts, chunkEnds] = localListChunkFiles(folderPath, prefix);

if hasSingle && ~isempty(chunkPaths)
    error('LoadNpyRecordingMeta:AmbiguousMetadata', ...
        'Both single and chunked %s files exist in %s.', prefix, folderPath);
end
if ~hasSingle && isempty(chunkPaths)
    return;
end

if hasSingle
    vectorLength = localGetVectorLength(singlePath, prefix);
    sourceStartIndex = 1;
    if vectorLength ~= sourceFiles.totalFrames
        if sourceFiles.isDirectFile && ...
                sourceFiles.frameGlobalEndsZero(1) + 1 <= vectorLength
            sourceStartIndex = sourceFiles.frameGlobalStartsZero(1) + 1;
        else
            error('LoadNpyRecordingMeta:MetadataLengthMismatch', ...
                '%s contains %d values; expected %d.', ...
                singlePath, vectorLength, sourceFiles.totalFrames);
        end
    end
    sources = struct('path', singlePath, 'startFrame', 1, ...
        'endFrame', sourceFiles.totalFrames, ...
        'count', sourceFiles.totalFrames, ...
        'sourceStartIndex', sourceStartIndex, ...
        'fileStartZero', sourceFiles.frameGlobalStartsZero(1), ...
        'fileEndZero', sourceFiles.frameGlobalEndsZero(end));
    return;
end

if sourceFiles.isDirectFile
    wantedStart = sourceFiles.frameGlobalStartsZero(1);
    wantedEnd = sourceFiles.frameGlobalEndsZero(1);
    match = find(chunkStarts == wantedStart & chunkEnds == wantedEnd);
    if numel(match) ~= 1
        error('LoadNpyRecordingMeta:MetadataRangeMismatch', ...
            ['Chunked %s files exist, but none uniquely matches the direct ' ...
             'frame file range %d-%d.'], prefix, wantedStart, wantedEnd);
    end
    vectorLength = localGetVectorLength(chunkPaths{match}, prefix);
    expectedCount = wantedEnd - wantedStart + 1;
    if vectorLength ~= expectedCount
        error('LoadNpyRecordingMeta:MetadataLengthMismatch', ...
            '%s contains %d values; its name encodes %d.', ...
            chunkPaths{match}, vectorLength, expectedCount);
    end
    sources = struct('path', chunkPaths{match}, 'startFrame', 1, ...
        'endFrame', sourceFiles.totalFrames, 'count', sourceFiles.totalFrames, ...
        'sourceStartIndex', 1, 'fileStartZero', wantedStart, ...
        'fileEndZero', wantedEnd);
    return;
end

if strcmp(sourceFiles.storageMode, 'chunked')
    if numel(chunkPaths) ~= numel(sourceFiles.framePaths) || ...
            ~isequal(chunkStarts(:), sourceFiles.frameGlobalStartsZero(:)) || ...
            ~isequal(chunkEnds(:), sourceFiles.frameGlobalEndsZero(:))
        error('LoadNpyRecordingMeta:MetadataRangeMismatch', ...
            'Chunk ranges for %s do not exactly match the frame chunk ranges.', prefix);
    end
else
    expectedStart = 0;
    for i = 1:numel(chunkPaths)
        if chunkStarts(i) ~= expectedStart
            error('LoadNpyRecordingMeta:MetadataRangeMismatch', ...
                '%s chunks have a gap or overlap before %s.', prefix, chunkPaths{i});
        end
        expectedStart = chunkEnds(i) + 1;
    end
    if expectedStart ~= sourceFiles.totalFrames
        error('LoadNpyRecordingMeta:MetadataLengthMismatch', ...
            '%s chunks cover %d values; expected %d.', ...
            prefix, expectedStart, sourceFiles.totalFrames);
    end
end

sources = repmat(localEmptySourceScalar(), numel(chunkPaths), 1);
for i = 1:numel(chunkPaths)
    expectedCount = chunkEnds(i) - chunkStarts(i) + 1;
    vectorLength = localGetVectorLength(chunkPaths{i}, prefix);
    if vectorLength ~= expectedCount
        error('LoadNpyRecordingMeta:MetadataLengthMismatch', ...
            '%s contains %d values; its name encodes %d.', ...
            chunkPaths{i}, vectorLength, expectedCount);
    end
    sources(i) = struct('path', chunkPaths{i}, ...
        'startFrame', chunkStarts(i) + 1, ...
        'endFrame', chunkEnds(i) + 1, 'count', expectedCount, ...
        'sourceStartIndex', 1, 'fileStartZero', chunkStarts(i), ...
        'fileEndZero', chunkEnds(i));
end
end


function values = localReadVectorSelection(sources, startFrame, nFrames, label)
if isempty(sources)
    values = [];
    return;
end

requestEnd = startFrame + nFrames - 1;
values = [];
for i = 1:numel(sources)
    firstFrame = max(startFrame, sources(i).startFrame);
    lastFrame = min(requestEnd, sources(i).endFrame);
    if firstFrame > lastFrame
        continue;
    end
    localOffset = firstFrame - sources(i).startFrame;
    sourceStartIndex = sources(i).sourceStartIndex + localOffset;
    count = lastFrame - firstFrame + 1;
    part = localReadNpyVectorRange(sources(i).path, sourceStartIndex, count);
    values = [values; part(:)]; %#ok<AGROW>
end
if numel(values) ~= nFrames
    error('LoadNpyRecordingMeta:MetadataCoverage', ...
        'Requested %d %s values but resolved %d.', ...
        nFrames, label, numel(values));
end
end


function n = localGetVectorLength(filePath, label)
np = py.importlib.import_module('numpy');
pyArr = np.load(filePath, pyargs('allow_pickle', false, 'mmap_mode', 'r'));
kind = char(py.str(pyArr.dtype.kind));
if ~contains('buif', kind)
    error('LoadNpyRecordingMeta:BadMetadataType', ...
        '%s must contain a real numeric or logical array: %s', label, filePath);
end
n = double(pyArr.size);
if n < 1
    error('LoadNpyRecordingMeta:EmptyMetadata', ...
        '%s is empty: %s', label, filePath);
end
end


function arr = localReadNpyVectorRange(filePath, startIndex, count)
np = py.importlib.import_module('numpy');
pyArr = np.load(filePath, pyargs('allow_pickle', false, 'mmap_mode', 'r'));
flat = np.ravel(pyArr);
startZero = int64(startIndex - 1);
stopZero = int64(startIndex - 1 + count);
idx = np.arange(startZero, stopZero);
pySub = np.take(flat, idx, int32(0));
arr = localConvertPyArray(pySub);
end


function timeVecFile = localCameraTimesToTimeVector(camUs, metadata, nFrames)
if isempty(camUs)
    timeVecFile = nan([nFrames 1]);
    return;
end
if numel(camUs) ~= nFrames
    error('LoadNpyRecordingMeta:TimestampLengthMismatch', ...
        'Loaded %d camera timestamps for %d frames.', numel(camUs), nFrames);
end
if isfield(metadata, 'capture_start_unix_s') && ...
        isnumeric(metadata.capture_start_unix_s) && ...
        isscalar(metadata.capture_start_unix_s) && ...
        isfinite(metadata.capture_start_unix_s)
    tUnix = double(metadata.capture_start_unix_s) + camUs / 1e6;
    dt = datetime(tUnix, 'ConvertFrom', 'posixtime');
    timeVecFile = datenum(dt);
else
    timeVecFile = camUs / 1e6;
end
timeVecFile = timeVecFile(:);
end


function info = localBuildInfo(folderPath, metadata, sourceFiles, exposureMode, exposureSequenceUs)
info = struct();
info.fileType = '.npy';
info.imageSize = sourceFiles.imageSize;

sample = localReadNpyFrame(sourceFiles.framePaths{1}, 1);
info.nBits = localInferNBits(sample);

warnState = warning('off', 'all');
info.name = struct();
try
    info.name = GetParamsFromFileName(folderPath);
catch
    info.name = struct();
end
warning(warnState);

if isfield(metadata, 'config') && isstruct(metadata.config)
    cfg = metadata.config;
    if isfield(cfg, 'frame_rate_hz') && isnumeric(cfg.frame_rate_hz)
        info.name.FR = double(cfg.frame_rate_hz);
        info.cam.AcquisitionFrameRate = double(cfg.frame_rate_hz);
    elseif isfield(cfg, 'acquisition_frame_rate') && ...
            isnumeric(cfg.acquisition_frame_rate)
        info.name.FR = double(cfg.acquisition_frame_rate);
        info.cam.AcquisitionFrameRate = double(cfg.acquisition_frame_rate);
    end
    if isfield(cfg, 'black_level') && isnumeric(cfg.black_level)
        info.name.BL = double(cfg.black_level);
    end
    if isfield(cfg, 'gain') && isnumeric(cfg.gain)
        info.name.Gain = double(cfg.gain);
    end
    if ~strcmp(exposureMode, 'sequencer') && ...
            isfield(cfg, 'exposure_time') && isnumeric(cfg.exposure_time) && ...
            isscalar(cfg.exposure_time) && isfinite(cfg.exposure_time)
        expT = double(cfg.exposure_time);
        if expT > 200
            expT = expT / 1000;
        end
        info.name.expT = expT;
    elseif numel(exposureSequenceUs) == 1
        info.name.expT = exposureSequenceUs(1) / 1000;
    elseif strcmp(exposureMode, 'sequencer')
        info.name.expT = NaN;
    end
end

if isfield(metadata, 'camera_serial_number') && ~isempty(metadata.camera_serial_number)
    info.camera_serial_number = localToChar(metadata.camera_serial_number);
elseif isfield(metadata, 'camera_identity') && isstruct(metadata.camera_identity) && ...
        isfield(metadata.camera_identity, 'serial_number') && ...
        ~isempty(metadata.camera_identity.serial_number)
    info.camera_serial_number = localToChar(metadata.camera_identity.serial_number);
end
if isfield(info, 'camera_serial_number') && ~isempty(info.camera_serial_number)
    info.cameraSN = localToChar(info.camera_serial_number);
end

if isfield(metadata, 'camera_model') && ~isempty(metadata.camera_model)
    info.cameraModel = localToChar(metadata.camera_model);
elseif isfield(metadata, 'camera_identity') && isstruct(metadata.camera_identity) && ...
        isfield(metadata.camera_identity, 'model_name') && ...
        ~isempty(metadata.camera_identity.model_name)
    info.cameraModel = localToChar(metadata.camera_identity.model_name);
elseif isfield(metadata, 'model_name') && ~isempty(metadata.model_name)
    info.cameraModel = localToChar(metadata.model_name);
end

if isfield(metadata, 'actual_gain_estimation') && ...
        isstruct(metadata.actual_gain_estimation)
    age = metadata.actual_gain_estimation;
    if isfield(age, 'gain_db') && ...
            (~isfield(info.name, 'Gain') || isnan(info.name.Gain))
        info.name.Gain = double(age.gain_db);
    end
    if isfield(age, 'nbits') && ...
            (~isfield(info, 'nBits') || isempty(info.nBits) || isnan(info.nBits))
        info.nBits = double(age.nbits);
    end
end
if isfield(metadata, 'dtype')
    info.dtype = metadata.dtype;
end
if isfield(metadata, 'shape')
    info.shape = metadata.shape;
end
info.storageMode = sourceFiles.storageMode;
end


function [mode, sequenceUs] = localGetExposureSettings(metadata)
mode = 'unknown';
sequenceUs = [];
cfg = struct();
if isfield(metadata, 'config') && isstruct(metadata.config)
    cfg = metadata.config;
end

if isfield(metadata, 'exposure_mode') && ~isempty(metadata.exposure_mode)
    mode = lower(strtrim(localToChar(metadata.exposure_mode)));
elseif isfield(cfg, 'exposure_times_us') && ~isempty(cfg.exposure_times_us)
    mode = 'sequencer';
elseif isfield(cfg, 'exposure_time') && ~isempty(cfg.exposure_time)
    mode = 'fixed';
end

if isfield(metadata, 'exposure_sequence_us') && ...
        ~isempty(metadata.exposure_sequence_us)
    sequenceUs = localNumericVector( ...
        metadata.exposure_sequence_us, 'metadata.exposure_sequence_us');
elseif isfield(cfg, 'exposure_times_us') && ~isempty(cfg.exposure_times_us)
    sequenceUs = localNumericVector( ...
        cfg.exposure_times_us, 'metadata.config.exposure_times_us');
elseif isfield(cfg, 'exposure_time') && ~isempty(cfg.exposure_time)
    sequenceUs = localNumericVector( ...
        cfg.exposure_time, 'metadata.config.exposure_time');
end
sequenceUs = reshape(sequenceUs, 1, []);
end


function values = localNumericVector(value, fieldName)
if isnumeric(value) || islogical(value)
    values = double(value(:));
elseif iscell(value) && all(cellfun(@(v) isnumeric(v) && isscalar(v), value(:)))
    values = cellfun(@double, value(:));
else
    error('LoadNpyRecordingMeta:BadMetadata', ...
        '%s must be a numeric array.', fieldName);
end
if isempty(values) || any(~isfinite(values)) || any(values <= 0)
    error('LoadNpyRecordingMeta:BadMetadata', ...
        '%s must contain finite positive exposure times in microseconds.', fieldName);
end
end


function frame = localReadNpyFrame(filePath, localIndex)
np = py.importlib.import_module('numpy');
pyArr = np.load(filePath, pyargs('allow_pickle', false, 'mmap_mode', 'r'));
pySub = np.take(pyArr, int64(localIndex - 1), int32(0));
frame = localConvertPyArray(pySub);
end


function arr = localConvertPyArray(pyArr)
dtypeName = lower(char(py.str(pyArr.dtype.name)));
switch dtypeName
    case 'uint8'
        arr = uint8(pyArr);
    case 'uint16'
        arr = uint16(pyArr);
    case 'uint32'
        arr = uint32(pyArr);
    case 'uint64'
        arr = uint64(pyArr);
    case 'int8'
        arr = int8(pyArr);
    case 'int16'
        arr = int16(pyArr);
    case 'int32'
        arr = int32(pyArr);
    case 'int64'
        arr = int64(pyArr);
    case {'single', 'float32'}
        arr = single(pyArr);
    case {'double', 'float64'}
        arr = double(pyArr);
    otherwise
        arr = double(pyArr);
end
end


function nBits = localInferNBits(rawFrames)
if isa(rawFrames, 'uint8')
    nBits = 8;
    return;
end
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


function [paths, starts, ends] = localListChunkFiles(folderPath, prefix)
files = dir(fullfile(folderPath, [prefix '_*.npy']));
paths = {};
starts = [];
ends = [];
for i = 1:numel(files)
    if contains(lower(files(i).name), '.tmp')
        continue;
    end
    parsed = localParseChunkName(files(i).name, prefix);
    if ~parsed.matched
        continue;
    end
    paths{end+1,1} = fullfile(folderPath, files(i).name); %#ok<AGROW>
    starts(end+1,1) = parsed.startZero; %#ok<AGROW>
    ends(end+1,1) = parsed.endZero; %#ok<AGROW>
end
if ~isempty(paths)
    [starts, order] = sort(starts);
    ends = ends(order);
    paths = paths(order);
end
end


function parsed = localParseChunkName(fileName, prefix)
pattern = ['^' regexptranslate('escape', prefix) ...
    '_(\d{8})_(\d{8})\.npy$'];
tokens = regexp(fileName, pattern, 'tokens', 'once');
parsed = struct('matched', ~isempty(tokens), 'startZero', NaN, 'endZero', NaN);
if ~isempty(tokens)
    parsed.startZero = str2double(tokens{1});
    parsed.endZero = str2double(tokens{2});
end
end


function tf = localIsChunkName(fileName, prefix)
parsed = localParseChunkName(fileName, prefix);
tf = parsed.matched;
end


function names = localTextList(value, fieldName)
if ischar(value)
    names = {value};
elseif isstring(value)
    names = cellstr(value(:));
elseif iscell(value)
    names = cell(size(value));
    for i = 1:numel(value)
        if ischar(value{i})
            names{i} = value{i};
        elseif isstring(value{i}) && isscalar(value{i})
            names{i} = char(value{i});
        else
            error('LoadNpyRecordingMeta:BadMetadata', ...
                '%s must contain only file names.', fieldName);
        end
    end
    names = names(:);
else
    error('LoadNpyRecordingMeta:BadMetadata', ...
        '%s must be a file name or list of file names.', fieldName);
end
end


function sources = localEmptySources()
sources = repmat(localEmptySourceScalar(), 0, 1);
end


function source = localEmptySourceScalar()
source = struct('path', '', 'startFrame', 0, 'endFrame', 0, ...
    'count', 0, 'sourceStartIndex', 1, ...
    'fileStartZero', 0, 'fileEndZero', 0);
end


function out = localToChar(value)
if isnumeric(value)
    out = num2str(value);
elseif isstring(value)
    out = char(value);
elseif ischar(value)
    out = value;
else
    out = char(string(value));
end
end
