%  ---------------------------------------------------------------------------------------------------------
% Standalone SCOS-NIRS analysis for NPY recordings. The SCOS pipeline is
% implemented in this file, followed by two-wavelength NIRS, rOEF, and rMRO2.
%  GUI mode:   - Choose the recording folder
%              - Choose widow size ( it will be used in stdfilter() function in order to calc the local std)
%              - Choose dark recording folder
%
%                First frame of the recording will appear, on witch the
%                user should draw a circle with the ROI (Region of Interest)
%
%                In the second time this function will run for the same
%                recording , the ROI is already saved , so ne need to
%                choose it again.
%                Main and dark recording folder names should be in the following format :
%                <Name>_Gain<X>dB_expT<>ms_FR<X>Hz_BL<>DU
%                Where expT -> exposure time in ms, FR -> Frame Rate, BL -> Black Level
%                If the dark recording is located in the same folder as the Main one, and starts with "background"
%                it is automatically recognized.
%
%  Command Mode: Same as GUI mode , but recName and windowSize variables must be specified.
%                plotFlag - [optional] defualt= true
%                maskInput - can be "true" (then all the image is taken as mask) or
%                a boolaen map the same size as the record.
%  ---------------------------------------------------------------------------------------------------------

function [timeVec,rawSpeckleContrast,corrSpeckleContrast,meanVec,info,results,nirs] = ...
    SCOSNIRSvsTime_WithNoiseSubtraction_Ver2( ...
        recName,backgroundName,windowSize,plotFlag,maskInput,nirsOptions)
% This file contains its own complete NPY loading, calibration, ROI-specific
% SCOS, BFI, and rBFI implementation. It deliberately does not call the
% separate SCOSvsTime_WithNoiseSubtraction_Ver2 entry point.
if nargin < 6 || isempty(nirsOptions)
    nirsOptions = struct();
end
if ~isstruct(nirsOptions) || ~isscalar(nirsOptions)
    error('SCOSNIRSvsTime:Options','nirsOptions must be a scalar structure.');
end
usePrecomputedResults = isfield(nirsOptions,'precomputedResults') && ...
    ~isempty(nirsOptions.precomputedResults);
calculationOptions = nirsOptions;

if usePrecomputedResults
    if nargin < 1 || isempty(recName)
        recName = 'precomputed-results';
    end
    if nargin < 2
        backgroundName = [];
    end
    if nargin < 3 || isempty(windowSize)
        windowSize = 7;
    end
    if nargin < 4 || isempty(plotFlag)
        plotFlag = true;
    end
    results = nirsOptions.precomputedResults;
    calculationOptions = rmfield(nirsOptions,'precomputedResults');
    timeVec = [];
    rawSpeckleContrast = {};
    corrSpeckleContrast = {};
    meanVec = {};
    info = struct('analysisMode','precomputedResults');
    nirs = localCalculateNirsFromScosResults(results,calculationOptions);
    results.nirs = nirs;
    localFinalizeNirsOutput(nirs,results,info,recName,backgroundName, ...
        windowSize,nirsOptions,calculationOptions,plotFlag);
    return
end

if nargin < 4
    plotFlag = true;
end
scriptDir = fileparts(mfilename('fullpath'));
addpath(fullfile(scriptDir,'baseFunc'))

%% Constants
timePeriodForP2P = 2; % [s]

%% Check input parameters
if nargin == 0 % GUI mode
    plotFlag = 1;
    if exist('.\lastRec.mat','file')
        lastF = load('.\lastRec.mat');
    else
        lastF.recName = [ fileparts(pwd) '\Records' ];
    end

    [recName] = uigetdir(fileparts(lastF.recName));
    if recName == 0; return; end % if 'Cancel' was pressed
    hasFramesNpy = exist(fullfile(recName,'frames.npy'),'file') == 2;
    hasChunkFrames = ~isempty(dir(fullfile(recName,'frames_*.npy')));
    if ~(hasFramesNpy || hasChunkFrames)
        errordlg(['No frame .npy files found in ' recName ])
        error(['No frame .npy files found in ' recName ]);
    end

    save('.\lastRec.mat','recName')

    maxWindowSize = 50; minWindowSize = 3;
    answer = inputdlg('Window Size','',[1 25],{'7'});
    windowSize = str2double(answer{1});
    if isnan(windowSize) || windowSize > maxWindowSize || windowSize < minWindowSize
        errordlg(['Window Size must be a number between ' num2str(minWindowSize)  ' and ' num2str( num2str(maxWindowSize) ) ]);
        error(['Window Size must be a number between ' num2str(minWindowSize)  ' and ' num2str( num2str(maxWindowSize) ) ])
    end
    clear answer
end

if nargin == 0  || isempty(backgroundName)
    if exist([recName , '_dark'],'dir')
        backgroundName = [recName , '_dark'];
    else
        dir_Background = [ dir([fileparts(recName) , '\DarkIm*']) dir([fileparts(recName) , '\background*']) dir([fileparts(recName) , '\BG_*'])   ] ;

        if  isempty(dir_Background) || numel(dir_Background) > 1
            backgroundName = uigetdir( fileparts(recName) ,'Please Select the background');
        else
            backgroundName = fullfile(fileparts(recName),dir_Background(1).name);
        end
        if isequal(backgroundName,0)
            disp('Aborting...')
            return;
        end
    end
end

%% Create Mask
upFolders = strsplit(recName,filesep);
rawName = strrep( strjoin(upFolders(max(1,end-2):end),'; '), '_',' '); %#ok<NASGU>

if exist(recName,'file') == 7 % it's a folder
    recSavePrefix = [ recName filesep ];
else % it's a file
    recSavePrefix = [ recName(1:find(recName=='.',1,'last')-1) '_' ];
end

isNpyRecord = exist(recName,'dir') == 7 && (exist(fullfile(recName,'frames.npy'),'file') == 2 || ~isempty(dir(fullfile(recName,'frames_*.npy'))));

if isNpyRecord
    [timeVecMetadata, info, sourceFiles] = LoadNpyRecordingMeta(recName);
    nOfFrames = sourceFiles.totalFrames;

    perFrameExposureUs = [];
    if isfield(info,'exposureTimesUs')
        perFrameExposureUs = info.exposureTimesUs;
    end
    exposureSequenceUs = [];
    if isfield(info,'exposureSequenceUs')
        exposureSequenceUs = info.exposureSequenceUs;
    elseif isfield(info,'name') && isfield(info.name,'expT') && ...
            isnumeric(info.name.expT) && isscalar(info.name.expT) && isfinite(info.name.expT)
        exposureSequenceUs = double(info.name.expT) * 1000; % legacy info.name.expT is ms
    end
    [exposureGroupIndex, exposureGroupValuesUs, exposureGroupDetails] = ...
        GroupExposureFrames(perFrameExposureUs, exposureSequenceUs, nOfFrames);
    nExposureGroups = numel(exposureGroupValuesUs);
    isMultipleExposure = nExposureGroups > 1;

    sequencerSetIds = [];
    if isfield(info,'sequencerSetIds')
        sequencerSetIds = info.sequencerSetIds;
    end
    if isempty(sequencerSetIds)
        sequencerSetIds = nan(nOfFrames,1);
    else
        sequencerSetIds = double(sequencerSetIds(:));
        if numel(sequencerSetIds) ~= nOfFrames
            error('SCOSNIRSvsTime:SequencerSetLength', ...
                'sequencerSetIds contains %d values for %d frames.',numel(sequencerSetIds),nOfFrames);
        end
    end

    % A mixed-exposure preview would average different signal/noise regimes.
    % Use only the first exposure condition to define the common spatial ROI.
    previewIndices = find(exposureGroupIndex == 1);
    nPreview = min(20,numel(previewIndices));
    previewRec = zeros([sourceFiles.imageSize nPreview]);
    for k=1:nPreview
        previewRec(:,:,k) = double(LoadNpyRecordingFrame(recName,previewIndices(k),sourceFiles));
    end
    mean_frame = mean(previewRec,3);
    im1 = previewRec(:,:,1);
else
    error('SCOSNIRSvsTime_WithNoiseSubtraction_Ver2 now expects recName to be a folder containing frame .npy files');
end

maskFile = [recSavePrefix 'Mask.mat'];
if exist('maskInput','var')
    if isequal(maskInput, true)
        masks = {true(size(mean_frame))};
        totMask = masks{1};
        disp('Mask is the whole image')
    elseif iscell(maskInput)
        masks = maskInput;
        for k=1:numel(masks)
            if ~isequal( size(masks{k}), size(mean_frame) )
                error('wrong maskInput size, should be the same as the recording');
            end
        end
        totMask = masks{1};
        for k=2:numel(masks)
            totMask = totMask | masks{k};
        end
        disp('Input mask is a cell array')
    elseif islogical(maskInput)
        if ~isequal( size(maskInput), size(mean_frame) )
            error('wrong maskInput');
        end
        masks = {maskInput};
        totMask = masks{1};
        disp('Input single mask')
    else
        error('wrong maskInput type');
    end
    loadExistingFile_flag = 0;
else
    if ~exist(maskFile,'file')
        loadExistingFile_flag = 0;
    else
        if nargin == 0 % GUI mode
            answer = questdlg('Mask file already exist, do you want to define it again?','','Yes','No','No');
            loadExistingFile_flag = strcmp(answer,'No');
        else      % Command line mode -> load the saved mask
            loadExistingFile_flag = 1;
        end
    end
end

% -- get ROI if needed and cut the margins
ws2 = ceil(windowSize/2); % for margins marking as false
if ~exist('masks','var')
    if ~loadExistingFile_flag
        masks = {};
        channels.Centers = [];
        channels.Radii   = [];
        meanImForMask = mean_frame;
        addMore = true; ch = 1; figMask = [];
        while addMore
            [maskTemp , circ , figMask] = GetROI(meanImForMask,windowSize);
            masks{ch} = maskTemp; %#ok<AGROW>
            channels.Centers(ch,:) = circ.Center;
            channels.Radii(ch,1)   = circ.Radius;
            answer = questdlg('Add another ROI?','Channels','Yes','No','No');
            addMore = strcmp(answer,'Yes');
            ch = ch + 1;
        end
        totMask = masks{1};
        for k = 2:numel(masks)
            totMask = totMask | masks{k};
        end
        save(maskFile,'masks','channels','totMask');
        if ~isempty(figMask)
            savefig(figMask,[recName '\maskIm.fig'])
        end
    else
        M = load(maskFile);
        if isfield(M,'mask')
            masks{1} = false(size(M.mask));
            masks{1}(ws2+1:end-ws2,ws2+1:end-ws2) = ...
                M.mask(ws2+1:end-ws2,ws2+1:end-ws2);
            totMask = M.mask > 0;
            channels.Centers = M.circ.Center;
            channels.Radii  = M.circ.Radius;
        else
            load(maskFile); %#ok<LOAD>
        end
    end
end
for k=1:numel(masks)
    masks{k}( [ 1:ws2 (end-ws2+1):end ],:) = false;
    masks{k}( : , [ 1:ws2 (end-ws2+1):end ]) = false;
end
totMask( [ 1:ws2 (end-ws2+1):end ], : ) = false;
totMask( : , [ 1:ws2 (end-ws2+1):end ]) = false;

%% Check info
upFolders = strsplit(recName,filesep);
shortRecName = strjoin(upFolders(max(1,end-2):end)); %#ok<NASGU>

if ~isequal(backgroundName,0)
    if exist(backgroundName,'dir') == 7 && (exist(fullfile(backgroundName,'frames.npy'),'file') == 2 || ~isempty(dir(fullfile(backgroundName,'frames_*.npy'))))
        [~,info_background] = LoadNpyRecordingMeta(backgroundName);
    else
        info_background = GetRecordInfo(backgroundName);
    end
    fields = {'Gain','BL'};
    if ~isMultipleExposure
        fields = [{'expT'} fields];
    end
    for fi = 1:numel(fields)
        param = fields{fi};
        if isfield(info_background,'name') && isfield(info_background.name,param) && ...
                isfield(info,'name') && isfield(info.name,param) && ...
                isnumeric(info_background.name.(param)) && isnumeric(info.name.(param)) && ...
                ~isnan(info_background.name.(param)) && ~isnan(info.name.(param)) && ...
                info_background.name.(param) ~= info.name.(param)
            error('Background.%s=%g   Record.%s=%g',param, info_background.name.(param), param, info.name.(param));
        end
    end
end

if isfield(info,'cam') && isfield(info.cam,'AcquisitionFrameRate')
    frameRate = info.cam.AcquisitionFrameRate;
else
    if ~isfield(info.name,'FR') || isnan(info.name.FR)
        error('Frame Rate must be part of the recording name as "FR"');
    end
    frameRate = info.name.FR;
end

[allTimeVec, usedCameraTimestamps] = BuildExposureTimeAxis(timeVecMetadata,nOfFrames,frameRate);
timeVecFile = timeVecMetadata;
if isempty(timeVecFile) || all(isnan(timeVecFile))
    % Preserve the legacy saved timeVecFile convention (1/frameRate origin),
    % while allTimeVec itself is normalized to zero by BuildExposureTimeAxis.
    timeVecFile = (1:nOfFrames)' ./ frameRate;
end
if usedCameraTimestamps
    info.timeAxisSource = 'camera_timestamp';
else
    info.timeAxisSource = 'frame_rate_fallback';
end

if ~isfield(info.name , 'BL' ) || ~isnumeric(info.name.BL) || isempty(info.name.BL)
    BlackLevel = 0;
else
    BlackLevel = info.name.BL;
end

%% Get Background and Background Noise
start_calib_time = tic;
disp('Load Background');
if ~exist(backgroundName,'file')
    error([backgroundName,' does not exist!']);
end
[backgroundByExposure, darkVarByExposure, darkCalibrationInfo] = ...
    localLoadDarkCorrections(backgroundName,info_background,mean_frame,recName, ...
        exposureGroupValuesUs,nExposureGroups);
darkVarPerWindowByExposure = cell(1,nExposureGroups);
for exposureIdx = 1:nExposureGroups
    darkVarPerWindowByExposure{exposureIdx} = ...
        imboxfilt(darkVarByExposure{exposureIdx},windowSize);
end

%% Get G[DU/e]
nOfBits = info.nBits;
actualGain = GetActualGain(info);

%% Calc spatialNoise
spatialCalibration = localBuildSpatialCorrections(recName,sourceFiles, ...
    exposureGroupIndex,exposureGroupValuesUs,backgroundByExposure, ...
    BlackLevel,masks,totMask,windowSize,actualGain,plotFlag);

disp('Calibration Time')
toc(start_calib_time)

%% Decrease Image Size
[y,x] = find(totMask);
roi_lims  = [ min(y)-windowSize  , max(y)+windowSize
              min(x)-windowSize  , max(x)+windowSize ];

roi_lims( roi_lims < 1 ) = 1;
if roi_lims(1,2) > info.imageSize(1)
    roi_lims(1,2) = info.imageSize(1);
end
if roi_lims(2,2) > info.imageSize(2)
    roi_lims(2,2) = info.imageSize(2);
end
roi.y = roi_lims(1,1):roi_lims(1,2);
roi.x = roi_lims(2,1):roi_lims(2,2);

masks_cut = cell(size(masks));
for ch = 1:numel(masks)
    masks_cut{ch} = masks{ch}(roi.y  , roi.x);
end

nOfChannels = numel(masks);
analysisCalibration = repmat(struct(),1,nExposureGroups);
for exposureIdx = 1:nExposureGroups
    analysisCalibration(exposureIdx).exposureTimeUs = exposureGroupValuesUs(exposureIdx);
    analysisCalibration(exposureIdx).background = backgroundByExposure{exposureIdx};
    analysisCalibration(exposureIdx).fitI_A_cut_byCh = cell(1,nOfChannels);
    analysisCalibration(exposureIdx).fitI_B_cut_byCh = cell(1,nOfChannels);
    for channelIdx = 1:nOfChannels
        analysisCalibration(exposureIdx).fitI_A_cut_byCh{channelIdx} = ...
            spatialCalibration(exposureIdx).fitI_A_byCh{channelIdx}(roi.y,roi.x);
        analysisCalibration(exposureIdx).fitI_B_cut_byCh{channelIdx} = ...
            spatialCalibration(exposureIdx).fitI_B_byCh{channelIdx}(roi.y,roi.x);
    end
    analysisCalibration(exposureIdx).spVar_cut = ...
        spatialCalibration(exposureIdx).spVar(roi.y,roi.x);
    analysisCalibration(exposureIdx).darkVarPerWindow_cut = ...
        darkVarPerWindowByExposure{exposureIdx}(roi.y,roi.x);
end

%% Calc Specle Contrast
disp(['Calculating SCOS on "' recName '" ... ']);
disp(['Mono' num2str(nOfBits)]);
frameNames = cell(nOfFrames,1);

im1 = double(im1);

devide_by = 1;
if nOfBits == 12  && all(mod(im1(:),2^4) == 0)
    devide_by = 2^4;
elseif nOfBits == 10  && all(mod(im1(:),2^6) == 0)
    devide_by = 2^6;
end

seriesTemplate = struct('frameIndices',[],'frameNames',{{}}, ...
    'rawSpeckleContrast',[],'corrSpeckleContrast',[],'meanIntensity',[], ...
    'writeCount',0);
exposureSeries = repmat(seriesTemplate,1,nExposureGroups);
for exposureIdx = 1:nExposureGroups
    indices = find(exposureGroupIndex == exposureIdx);
    nSeriesFrames = numel(indices);
    exposureSeries(exposureIdx).frameIndices = indices;
    exposureSeries(exposureIdx).frameNames = cell(nSeriesFrames,1);
    exposureSeries(exposureIdx).rawSpeckleContrast = nan(nSeriesFrames,nOfChannels);
    exposureSeries(exposureIdx).corrSpeckleContrast = nan(nSeriesFrames,nOfChannels);
    exposureSeries(exposureIdx).meanIntensity = nan(nSeriesFrames,nOfChannels);
end

start_scos = tic;

batchSize = 1000;
for batchStart = 1:batchSize:nOfFrames
    batchCount = min(batchSize, nOfFrames - batchStart + 1);
    [batchRec,~,~,batchSourceFiles] = LoadNpyRecordingRange(recName,batchStart,batchCount);

    for j = 1:batchCount
        i = batchStart + j - 1;

        if i == 50
            time50frames = toc(start_scos);
            fprintf('\n Estimated Time = %g min (%d frames)\n',round(time50frames/50*nOfFrames/60,2), nOfFrames)
        end
        if mod(i,200) == 0
            fprintf('%d\t',i);
            if mod(i,2000) == 0
                fprintf('\n');
            end
        end

        frameNames{i} = batchSourceFiles.frameNames{j};
        exposureIdx = exposureGroupIndex(i);
        seriesPosition = exposureSeries(exposureIdx).writeCount + 1;
        [rawRow,corrRow,meanRow] = localCalculateScosFrame( ...
            batchRec(:,:,j),devide_by,BlackLevel,analysisCalibration(exposureIdx), ...
            roi,masks_cut,windowSize,actualGain);
        exposureSeries(exposureIdx).rawSpeckleContrast(seriesPosition,:) = rawRow;
        exposureSeries(exposureIdx).corrSpeckleContrast(seriesPosition,:) = corrRow;
        exposureSeries(exposureIdx).meanIntensity(seriesPosition,:) = meanRow;
        exposureSeries(exposureIdx).frameNames{seriesPosition} = frameNames{i};
        exposureSeries(exposureIdx).writeCount = seriesPosition;

        if seriesPosition == 1
            fprintf('[EXPOSURE %.12g us] <I>=%.3g DU, K_raw=%.5g, K_corr=%.5g\n', ...
                exposureGroupValuesUs(exposureIdx),meanRow(1),rawRow(1),corrRow(1));
        end
    end

    clear batchRec batchSourceFiles
end
fprintf('\n');

%% Build exposure-separated results
if isfield(info,'exposureMode') && ~isempty(info.exposureMode)
    results.exposureMode = char(info.exposureMode);
elseif isMultipleExposure
    results.exposureMode = 'sequencer';
else
    results.exposureMode = 'fixed';
end
results.exposureSequenceUs = exposureSequenceUs;
results.timeAxisSource = info.timeAxisSource;
results.unusedExposureSequenceUs = exposureGroupDetails.unusedSequenceUs;
results.darkCalibration = darkCalibrationInfo;
results.byExposure = struct([]);

for exposureIdx = 1:nExposureGroups
    indices = exposureSeries(exposureIdx).frameIndices;
    exposureTimeVec = allTimeVec(indices);
    corrMatrix = exposureSeries(exposureIdx).corrSpeckleContrast;
    bfiMatrix = 1 ./ corrMatrix;
    rbfiMatrix = localCalculateRelativeBFI(bfiMatrix,exposureTimeVec);

    actualExposureUs = [];
    if ~isempty(perFrameExposureUs)
        actualExposureUs = double(perFrameExposureUs(indices));
        actualExposureUs = actualExposureUs(:);
    elseif isfinite(exposureGroupValuesUs(exposureIdx))
        actualExposureUs = repmat(exposureGroupValuesUs(exposureIdx),numel(indices),1);
    end

    exposureResult = struct();
    exposureResult.exposureTimeUs = exposureGroupDetails.actualMedianUs(exposureIdx);
    exposureResult.requestedExposureTimeUs = exposureGroupValuesUs(exposureIdx);
    exposureResult.actualExposureTimesUs = actualExposureUs;
    exposureResult.frameIndices = indices;
    exposureResult.sequencerSetIds = sequencerSetIds(indices);
    if all(isnan(exposureResult.sequencerSetIds))
        exposureResult.sequencerSetIds = [];
    end
    exposureResult.timeVec = exposureTimeVec;
    exposureResult.rawSpeckleContrast = exposureSeries(exposureIdx).rawSpeckleContrast;
    exposureResult.corrSpeckleContrast = corrMatrix;
    exposureResult.BFI = bfiMatrix;
    exposureResult.rBFI = rbfiMatrix;
    exposureResult.meanIntensity = exposureSeries(exposureIdx).meanIntensity;
    exposureResult.frameNames = exposureSeries(exposureIdx).frameNames;
    if numel(exposureTimeVec) > 1 && median(diff(exposureTimeVec)) > 0
        exposureResult.effectiveFrameRateHz = 1 / median(diff(exposureTimeVec));
    else
        exposureResult.effectiveFrameRateHz = NaN;
    end
    if exposureIdx == 1
        results.byExposure = exposureResult;
    else
        results.byExposure(exposureIdx) = exposureResult;
    end
end

nirs = localCalculateNirsFromScosResults(results,calculationOptions);
results.nirs = nirs;

if ~isMultipleExposure
    timeVec = results.byExposure(1).timeVec;
    rawSpeckleContrast = localMatrixColumnsToCells(results.byExposure(1).rawSpeckleContrast);
    corrSpeckleContrast = localMatrixColumnsToCells(results.byExposure(1).corrSpeckleContrast);
    meanVec = localMatrixColumnsToCells(results.byExposure(1).meanIntensity);
    BFI_matrix = results.byExposure(1).BFI;
    meanI_matrix = results.byExposure(1).meanIntensity;
    p2p_time = timeVec<timePeriodForP2P; %#ok<NASGU>
else
    % The legacy outputs cannot represent multiple exposure-specific clocks
    % without interleaving incompatible conditions. Use results.byExposure.
    timeVec = [];
    rawSpeckleContrast = {};
    corrSpeckleContrast = {};
    meanVec = {};
    BFI_matrix = [];
    meanI_matrix = [];
    warning('SCOSNIRSvsTime:MultipleExposureResults', ...
        ['Multiple exposure conditions were analyzed separately. Legacy time-series ' ...
         'outputs are empty; use results.byExposure.']);
end

%% Save
stdStr = sprintf('Std%dx%d',windowSize,windowSize);
if exist([recSavePrefix 'Local' stdStr '.mat'],'file')
    delete([recSavePrefix 'Local' stdStr '.mat']);
end % just for it to have the right date

startDateTime = sourceFiles.startDateTime;
if isempty(startDateTime)
    startDateTime = char(datetime('now','Format','yyyy-MM-dd HH:mm:ss'));
end

if ~exist('channels','var')
    channels = struct('Centers',[],'Radii',[]);
end
results.channels = channels;

if ~isMultipleExposure
    % Preserve all legacy variables and file names for fixed/single-condition
    % recordings. The additional results variable is backward compatible.
    save([recSavePrefix 'Local' stdStr '_corr.mat'], ...
        'startDateTime','timeVec', 'corrSpeckleContrast' , 'rawSpeckleContrast', ...
        'meanVec', 'info','nOfChannels', 'recName','windowSize','timeVecFile', ...
        'frameNames','results');

    BFI_output = struct('timeVec',timeVec,'BFI',BFI_matrix,'meanI',meanI_matrix, ...
        'channels',channels,'results',results);
    save([recSavePrefix 'BFI_output.mat'],'-struct','BFI_output');

    for ch = 1:nOfChannels
        singleBFI = struct();
        singleBFI.timeVec = timeVec;
        singleBFI.BFI = BFI_matrix(:,ch);
        singleBFI.meanI = meanI_matrix(:,ch);
        singleBFI.results = localSelectResultChannel(results,ch);
        save([recSavePrefix sprintf('BFI_Ch%d.mat',ch)],'-struct','singleBFI');
    end
else
    % An interleaved legacy matrix would invite invalid cross-exposure
    % analysis. Multi-exposure MAT files expose results.byExposure only.
    save([recSavePrefix 'Local' stdStr '_corr.mat'], ...
        'startDateTime','results','info','nOfChannels','recName','windowSize', ...
        'timeVecFile','frameNames');
    BFI_output = struct('results',results,'channels',channels);
    save([recSavePrefix 'BFI_output.mat'],'-struct','BFI_output');
    for ch = 1:nOfChannels
        singleBFI = struct('results',localSelectResultChannel(results,ch));
        save([recSavePrefix sprintf('BFI_Ch%d.mat',ch)],'-struct','singleBFI');
    end
end

%% Plot exposure-separated results
if plotFlag
    localPlotExposureResults(results,recName,recSavePrefix,stdStr,isMultipleExposure);
end

%%
localFinalizeNirsOutput(nirs,results,info,recName,backgroundName, ...
    windowSize,nirsOptions,calculationOptions,plotFlag);
toc(start_scos)
end

function [backgroundByExposure, darkVarByExposure, calibrationInfo] = ...
        localLoadDarkCorrections(backgroundName,infoBackground,meanFrame,recName, ...
            exposureGroupValuesUs,nExposureGroups)
% Dark data recorded at several exposures are never averaged together.
% If only one Dark condition (or an old Dark recording without exposure
% metadata) exists, it is reused deliberately and recorded as a limitation.

requiredBackgroundFrames = 400;
backgroundByExposure = cell(1,nExposureGroups);
darkVarByExposure = cell(1,nExposureGroups);
calibrationInfo = repmat(struct('sourceExposureTimeUs',NaN, ...
    'sharedAcrossExposure',false,'frameCount',0,'source',backgroundName),1,nExposureGroups);

isNpyBackground = exist(backgroundName,'dir') == 7 && ...
    (exist(fullfile(backgroundName,'frames.npy'),'file') == 2 || ...
     ~isempty(dir(fullfile(backgroundName,'frames_*.npy'))));

if isNpyBackground
    [~,backgroundInfo,backgroundSourceFiles] = LoadNpyRecordingMeta(backgroundName);
    backgroundExposureTimesUs = [];
    if isfield(backgroundInfo,'exposureTimesUs')
        backgroundExposureTimesUs = backgroundInfo.exposureTimesUs;
    end
    backgroundSequenceUs = [];
    if isfield(backgroundInfo,'exposureSequenceUs')
        backgroundSequenceUs = backgroundInfo.exposureSequenceUs;
    elseif isfield(backgroundInfo,'name') && isfield(backgroundInfo.name,'expT') && ...
            isnumeric(backgroundInfo.name.expT) && isscalar(backgroundInfo.name.expT) && ...
            isfinite(backgroundInfo.name.expT)
        backgroundSequenceUs = double(backgroundInfo.name.expT) * 1000;
    end
    [backgroundGroups,backgroundGroupValuesUs,backgroundGroupDetails] = ...
        GroupExposureFrames(backgroundExposureTimesUs,backgroundSequenceUs, ...
            backgroundSourceFiles.totalFrames);

    backgroundBlackLevel = localInfoBlackLevel(backgroundInfo);
    if isscalar(backgroundGroupValuesUs)
        indices = find(backgroundGroups == 1);
        [sharedBackground,sharedDarkVar] = localReadNpyDarkStatistics( ...
            backgroundName,backgroundSourceFiles,indices,requiredBackgroundFrames, ...
            backgroundBlackLevel);
        [sharedBackground,sharedDarkVar] = localAlignDarkSize( ...
            sharedBackground,sharedDarkVar,meanFrame,recName);
        for exposureIdx = 1:nExposureGroups
            backgroundByExposure{exposureIdx} = sharedBackground;
            darkVarByExposure{exposureIdx} = sharedDarkVar;
            calibrationInfo(exposureIdx).sourceExposureTimeUs = ...
                backgroundGroupDetails.actualMedianUs(1);
            calibrationInfo(exposureIdx).sharedAcrossExposure = nExposureGroups > 1;
            calibrationInfo(exposureIdx).frameCount = requiredBackgroundFrames;
        end
        if nExposureGroups > 1
            localWarnSharedDarkCorrection();
        end
        return;
    end

    for exposureIdx = 1:nExposureGroups
        matchingBackgroundGroup = localFindExposureMatch( ...
            exposureGroupValuesUs(exposureIdx),backgroundGroupValuesUs);
        if isempty(matchingBackgroundGroup)
            error('SCOSNIRSvsTime:MissingDarkExposure', ...
                ['Dark recording has no condition matching exposure %.12g us. ' ...
                 'Different Dark exposures will not be averaged as a fallback.'], ...
                exposureGroupValuesUs(exposureIdx));
        end
        indices = find(backgroundGroups == matchingBackgroundGroup);
        [background,darkVar] = localReadNpyDarkStatistics( ...
            backgroundName,backgroundSourceFiles,indices,requiredBackgroundFrames, ...
            backgroundBlackLevel);
        [background,darkVar] = localAlignDarkSize(background,darkVar,meanFrame,recName);
        backgroundByExposure{exposureIdx} = background;
        darkVarByExposure{exposureIdx} = darkVar;
        calibrationInfo(exposureIdx).sourceExposureTimeUs = ...
            backgroundGroupDetails.actualMedianUs(matchingBackgroundGroup);
        calibrationInfo(exposureIdx).frameCount = requiredBackgroundFrames;
    end
    return;
end

% Legacy TIFF/AVI/MAT Dark recordings do not carry per-frame exposure data.
% Preserve their established loading path, then reuse the one correction for
% every exposure with an explicit warning and metadata flag.
[background,darkVar,nBackgroundFrames] = localLoadLegacyDark( ...
    backgroundName,infoBackground,requiredBackgroundFrames);
[background,darkVar] = localAlignDarkSize(background,darkVar,meanFrame,recName);
for exposureIdx = 1:nExposureGroups
    backgroundByExposure{exposureIdx} = background;
    darkVarByExposure{exposureIdx} = darkVar;
    calibrationInfo(exposureIdx).sharedAcrossExposure = nExposureGroups > 1;
    calibrationInfo(exposureIdx).frameCount = nBackgroundFrames;
end
if nExposureGroups > 1
    localWarnSharedDarkCorrection();
end
end

function [background,darkVar] = localReadNpyDarkStatistics( ...
        backgroundName,sourceFiles,indices,requiredFrames,blackLevel)
if numel(indices) < requiredFrames
    error('SCOSNIRSvsTime:NotEnoughDarkFrames', ...
        'Dark exposure condition requires %d frames, but only %d were captured.', ...
        requiredFrames,numel(indices));
end
selected = indices(1:requiredFrames);
darkRecord = zeros([sourceFiles.imageSize requiredFrames]);
for frameIdx = 1:requiredFrames
    darkRecord(:,:,frameIdx) = double(LoadNpyRecordingFrame( ...
        backgroundName,selected(frameIdx),sourceFiles));
end
background = mean(darkRecord,3) - blackLevel;
darkVar = std(darkRecord,0,3).^2;
end

function [background,darkVar,nBackgroundFrames] = localLoadLegacyDark( ...
        backgroundName,infoBackground,requiredFrames)
blackLevel = localInfoBlackLevel(infoBackground);
if exist(backgroundName,'dir') == 7
    meanPath = fullfile(backgroundName,'meanIm.mat');
    if exist(meanPath,'file') == 2
        backgroundStruct = load(meanPath);
        if isfield(backgroundStruct,'nOfFrames')
            nBackgroundFrames = backgroundStruct.nOfFrames;
        else
            nBackgroundFrames = GetNumOfFrames(backgroundName);
        end
        if nBackgroundFrames < requiredFrames
            error('SCOSNIRSvsTime:NotEnoughDarkFrames', ...
                'Not enough Dark frames. Required %d, found %d.',requiredFrames,nBackgroundFrames);
        end
        if isfield(backgroundStruct,'recMean') && isfield(backgroundStruct,'recVar')
            background = backgroundStruct.recMean - blackLevel;
            darkVar = backgroundStruct.recVar;
        else
            [background,darkVar] = ReadRecordVarAndMean(backgroundName);
            background = background - blackLevel;
        end
    else
        nBackgroundFrames = GetNumOfFrames(backgroundName);
        if nBackgroundFrames < requiredFrames
            error('SCOSNIRSvsTime:NotEnoughDarkFrames', ...
                'Not enough Dark frames. Required %d, found %d.',requiredFrames,nBackgroundFrames);
        end
        [background,darkVar] = ReadRecordVarAndMean(backgroundName);
        background = background - blackLevel;
    end
elseif endsWith(lower(backgroundName),'.mat')
    backgroundStruct = load(backgroundName);
    names = fieldnames(backgroundStruct);
    if isfield(backgroundStruct,'recMean') && isfield(backgroundStruct,'recVar')
        background = backgroundStruct.recMean - blackLevel;
        darkVar = backgroundStruct.recVar;
        nBackgroundFrames = requiredFrames;
    else
        videoField = find(startsWith(names,'Video'),1,'first');
        if isempty(videoField)
            error('SCOSNIRSvsTime:InvalidDarkMat', ...
                'Dark MAT file must contain recMean/recVar or a Video* array.');
        end
        darkRecord = double(backgroundStruct.(names{videoField}));
        nBackgroundFrames = size(darkRecord,3);
        if nBackgroundFrames < requiredFrames
            error('SCOSNIRSvsTime:NotEnoughDarkFrames', ...
                'Not enough Dark frames. Required %d, found %d.',requiredFrames,nBackgroundFrames);
        end
        background = mean(darkRecord,3) - blackLevel;
        darkVar = std(darkRecord,0,3).^2;
    end
else
    error('SCOSNIRSvsTime:InvalidDarkPath','Unsupported Dark recording: %s',backgroundName);
end

if abs(mean(background(:),'omitnan')) > 3
    warning('SCOSNIRSvsTime:SuspiciousDarkLevel', ...
        'Suspicious mean Dark background level %.3g DU.',mean(background(:),'omitnan'));
end
end

function [background,darkVar] = localAlignDarkSize(background,darkVar,meanFrame,recName)
if isequal(size(background),size(meanFrame)) && isequal(size(darkVar),size(meanFrame))
    return;
end

roiPath = fullfile(recName,'ROI.mat');
if exist(roiPath,'file') == 2
    roiStruct = load(roiPath);
    if isfield(roiStruct,'xLimits') && isfield(roiStruct,'yLimits') && ...
            roiStruct.xLimits(1) >= 1 && roiStruct.yLimits(1) >= 1 && ...
            roiStruct.xLimits(end) <= size(background,2) && ...
            roiStruct.yLimits(end) <= size(background,1)
        background = background(roiStruct.yLimits(1):roiStruct.yLimits(2), ...
            roiStruct.xLimits(1):roiStruct.xLimits(2));
        darkVar = darkVar(roiStruct.yLimits(1):roiStruct.yLimits(2), ...
            roiStruct.xLimits(1):roiStruct.xLimits(2));
    end
end

if ~isequal(size(background),size(meanFrame)) || ~isequal(size(darkVar),size(meanFrame))
    error('SCOSNIRSvsTime:DarkImageSize', ...
        'Dark image size [%s] does not match recording image size [%s].', ...
        num2str(size(background)),num2str(size(meanFrame)));
end
end

function blackLevel = localInfoBlackLevel(info)
blackLevel = 0;
if isfield(info,'name') && isfield(info.name,'BL') && isnumeric(info.name.BL) && ...
        isscalar(info.name.BL) && isfinite(info.name.BL)
    blackLevel = double(info.name.BL);
end
end

function localWarnSharedDarkCorrection()
warning('SCOSNIRSvsTime:SharedDarkCorrection', ...
    ['A single Dark/noise correction is being reused for multiple exposure ' ...
     'conditions. Intensity and noise depend on exposure time; rigorous ' ...
     'comparison requires Dark data acquired separately at each exposure.']);
end

function matchingGroup = localFindExposureMatch(value,candidates)
matchingGroup = [];
if ~isfinite(value) || isempty(candidates)
    return;
end
try
    [groupIndex,~,details] = GroupExposureFrames(value,candidates,1);
    matchingGroup = find(details.sequenceToGroup == groupIndex(1),1,'first');
catch err
    if ~strcmp(err.identifier,'GroupExposureFrames:UnmatchedExposure')
        rethrow(err);
    end
end
end

function spatialCalibration = localBuildSpatialCorrections(recName,sourceFiles, ...
        exposureGroupIndex,exposureGroupValuesUs,backgroundByExposure, ...
        blackLevel,masks,totMask,windowSize,actualGain,plotFlag)
% Spatial coefficients are estimated independently for every applied
% exposure. Averaging alternating exposures here would mix both intensity
% and exposure-dependent noise before SCOS is calculated.

nExposureGroups = numel(exposureGroupValuesUs);
calibrationVersion = 2;
if nExposureGroups == 1
    cachePath = fullfile(recName,'smoothingCoefficients.mat');
else
    cachePath = fullfile(recName,'smoothingCoefficientsByExposure.mat');
end
if exist(cachePath,'file') == 2
    cached = load(cachePath);
    [cacheIsValid,cacheOrder] = localValidateSpatialCache(cached,calibrationVersion, ...
        sourceFiles.imageSize,windowSize,masks,exposureGroupValuesUs,actualGain);
    if cacheIsValid
        if nExposureGroups == 1
            disp('Load ROI-specific Spatial Noise and Smoothing Coefficients');
        else
            disp('Load exposure- and ROI-specific Spatial Noise and Smoothing Coefficients');
        end
        spatialCalibration = cached.spatialCalibration(cacheOrder);
        return;
    end
    warning('SCOSNIRSvsTime:StaleSpatialCache', ...
        ['Ignoring an incompatible spatial-calibration cache. The cache will be ' ...
         'recomputed with ROI-specific intensity fits and spatial shot-noise subtraction.']);
end

disp('Calc exposure- and ROI-specific Spatial Noise and Smoothing Coefficients');
spatialCalibration = repmat(struct(),1,nExposureGroups);
for exposureIdx = 1:nExposureGroups
    availableIndices = find(exposureGroupIndex == exposureIdx);
    desiredFrames = 600;
    if numel(availableIndices) > 1000
        desiredFrames = 1000;
    end
    nSpatialFrames = min(desiredFrames,numel(availableIndices));
    if nSpatialFrames < 2
        error('SCOSNIRSvsTime:NotEnoughSpatialFrames', ...
            'Exposure %.12g us requires at least two frames for spatial calibration.', ...
            exposureGroupValuesUs(exposureIdx));
    end
    if nSpatialFrames < desiredFrames
        warning('SCOSNIRSvsTime:FewSpatialFrames', ...
            'Exposure %.12g us uses only %d frames for spatial calibration.', ...
            exposureGroupValuesUs(exposureIdx),nSpatialFrames);
    end

    selected = availableIndices(1:nSpatialFrames);
    spatialRecord = zeros([sourceFiles.imageSize nSpatialFrames]);
    for frameIdx = 1:nSpatialFrames
        spatialRecord(:,:,frameIdx) = double(LoadNpyRecordingFrame( ...
            recName,selected(frameIdx),sourceFiles));
    end
    spatialRecord = spatialRecord - blackLevel;
    spatialImage = mean(spatialRecord,3) - backgroundByExposure{exposureIdx};
    spatialVarianceRaw = stdfilt(spatialImage,true(windowSize)).^2;
    spatialShotVariance = actualGain .* imboxfilt(spatialImage,windowSize) ./ nSpatialFrames;
    spatialVariance = max(spatialVarianceRaw - spatialShotVariance,0);
    fitI_A_byCh = cell(1,numel(masks));
    fitI_B_byCh = cell(1,numel(masks));
    for channelIdx = 1:numel(masks)
        [fitI_A_byCh{channelIdx},fitI_B_byCh{channelIdx}] = ...
            FitMeanIm(spatialRecord,masks{channelIdx},windowSize);
    end

    spatialCalibration(exposureIdx).exposureTimeUs = exposureGroupValuesUs(exposureIdx);
    spatialCalibration(exposureIdx).spVar = spatialVariance;
    spatialCalibration(exposureIdx).spVarRaw = spatialVarianceRaw;
    spatialCalibration(exposureIdx).spShotVar = spatialShotVariance;
    spatialCalibration(exposureIdx).fitI_A_byCh = fitI_A_byCh;
    spatialCalibration(exposureIdx).fitI_B_byCh = fitI_B_byCh;
    spatialCalibration(exposureIdx).spIm = spatialImage;
    spatialCalibration(exposureIdx).frameCount = nSpatialFrames;

    if plotFlag
        spatialFigure = my_imagesc(spatialImage);
        title(sprintf('Image average: %d frames, exposure %.12g us', ...
            nSpatialFrames,exposureGroupValuesUs(exposureIdx)));
        if nExposureGroups == 1
            figureName = 'spIm.fig';
        else
            figureName = sprintf('spIm_exp%sus.fig', ...
                localExposureFileLabel(exposureGroupValuesUs(exposureIdx)));
        end
        savefig(spatialFigure,fullfile(recName,figureName));
    end
end
savedCalibrationVersion = calibrationVersion;
savedWindowSize = windowSize;
savedMasks = masks;
savedMask = totMask;
savedExposureValuesUs = exposureGroupValuesUs;
savedActualGain = actualGain;
save(cachePath,'spatialCalibration','savedCalibrationVersion','savedWindowSize', ...
    'savedMasks','savedMask','savedExposureValuesUs','savedActualGain');
end

function [isValid,cacheOrder] = localValidateSpatialCache(cached,expectedVersion, ...
        imageSize,windowSize,masks,exposureValuesUs,actualGain)
isValid = false;
cacheOrder = [];
required = {'spatialCalibration','savedCalibrationVersion','savedWindowSize', ...
    'savedMasks','savedExposureValuesUs','savedActualGain'};
if ~all(isfield(cached,required)) || ...
        ~isnumeric(cached.savedCalibrationVersion) || ...
        ~isscalar(cached.savedCalibrationVersion) || ...
        cached.savedCalibrationVersion ~= expectedVersion || ...
        ~isnumeric(cached.savedWindowSize) || ~isscalar(cached.savedWindowSize) || ...
        cached.savedWindowSize ~= windowSize || ...
        ~iscell(cached.savedMasks) || ...
        ~isequal(cached.savedMasks,masks) || ...
        ~isnumeric(cached.savedActualGain) || ~isscalar(cached.savedActualGain) || ...
        ~isequaln(cached.savedActualGain,actualGain) || ...
        ~isnumeric(cached.savedExposureValuesUs) || ...
        numel(cached.savedExposureValuesUs) ~= numel(exposureValuesUs) || ...
        numel(cached.spatialCalibration) ~= numel(exposureValuesUs)
    return;
end

cacheOrder = zeros(1,numel(exposureValuesUs));
for exposureIdx = 1:numel(exposureValuesUs)
    matchingCacheExposure = localFindExposureMatch( ...
        exposureValuesUs(exposureIdx),cached.savedExposureValuesUs);
    if isempty(matchingCacheExposure) || matchingCacheExposure < 1
        cacheOrder = [];
        return;
    end
    cacheOrder(exposureIdx) = matchingCacheExposure;
end
if numel(unique(cacheOrder)) ~= numel(cacheOrder)
    cacheOrder = [];
    return;
end

for exposureIdx = 1:numel(cacheOrder)
    calibration = cached.spatialCalibration(cacheOrder(exposureIdx));
    requiredCalibration = {'spVar','spVarRaw','spShotVar','fitI_A_byCh', ...
        'fitI_B_byCh','spIm','frameCount'};
    if ~all(isfield(calibration,requiredCalibration)) || ...
            ~isequal(size(calibration.spVar),imageSize) || ...
            ~isequal(size(calibration.spVarRaw),imageSize) || ...
            ~isequal(size(calibration.spShotVar),imageSize) || ...
            numel(calibration.fitI_A_byCh) ~= numel(masks) || ...
            numel(calibration.fitI_B_byCh) ~= numel(masks)
        cacheOrder = [];
        return;
    end
    for channelIdx = 1:numel(masks)
        if ~isequal(size(calibration.fitI_A_byCh{channelIdx}),imageSize) || ...
                ~isequal(size(calibration.fitI_B_byCh{channelIdx}),imageSize)
            cacheOrder = [];
            return;
        end
    end
end
isValid = true;
end

function [rawRow,corrRow,meanRow] = localCalculateScosFrame(rawFrame,divideBy, ...
        blackLevel,calibration,roi,masksCut,windowSize,actualGain)
% One shared SCOS implementation is used for fixed and every sequencer
% exposure condition. Only the selected correction structure differs.
image = double(rawFrame) ./ divideBy - blackLevel - calibration.background;
imageCut = image(roi.y,roi.x);
localVariance = stdfilt(imageCut,true(windowSize)).^2;
nChannels = numel(masksCut);
rawRow = nan(1,nChannels);
corrRow = nan(1,nChannels);
meanRow = nan(1,nChannels);

for channelIdx = 1:nChannels
    mask = masksCut{channelIdx};
    meanIntensity = mean(imageCut(mask));
    fittedIntensity = calibration.fitI_A_cut_byCh{channelIdx} .* meanIntensity + ...
        calibration.fitI_B_cut_byCh{channelIdx};
    fittedIntensitySquared = fittedIntensity.^2;
    rawRow(channelIdx) = mean(localVariance(mask) ./ fittedIntensitySquared(mask));
    correctedNumerator = localVariance - actualGain .* fittedIntensity - ...
        calibration.spVar_cut - calibration.darkVarPerWindow_cut;
    corrRow(channelIdx) = mean(correctedNumerator(mask) ./ fittedIntensitySquared(mask));
    meanRow(channelIdx) = meanIntensity;
end
end

function relativeBFI = localCalculateRelativeBFI(bfi,timeVec)
relativeBFI = nan(size(bfi));
if isempty(bfi)
    return;
end
baselineMask = timeVec <= timeVec(1) + 10;
if ~any(baselineMask)
    baselineMask(1) = true;
end
longRecording = timeVec(end) - timeVec(1) > 120;
for channelIdx = 1:size(bfi,2)
    baselineValues = bfi(baselineMask,channelIdx);
    baselineValues = baselineValues(isfinite(baselineValues));
    if isempty(baselineValues)
        continue;
    end
    if longRecording
        reference = mean(baselineValues);
    else
        reference = prctile(baselineValues,5);
    end
    if isfinite(reference) && reference ~= 0
        relativeBFI(:,channelIdx) = bfi(:,channelIdx) ./ reference;
    end
end
end

function cells = localMatrixColumnsToCells(matrix)
cells = cell(1,size(matrix,2));
for columnIdx = 1:size(matrix,2)
    cells{columnIdx} = matrix(:,columnIdx);
end
end

function selected = localSelectResultChannel(results,channelIdx)
selected = results;
for exposureIdx = 1:numel(selected.byExposure)
    selected.byExposure(exposureIdx).rawSpeckleContrast = ...
        selected.byExposure(exposureIdx).rawSpeckleContrast(:,channelIdx);
    selected.byExposure(exposureIdx).corrSpeckleContrast = ...
        selected.byExposure(exposureIdx).corrSpeckleContrast(:,channelIdx);
    selected.byExposure(exposureIdx).BFI = ...
        selected.byExposure(exposureIdx).BFI(:,channelIdx);
    selected.byExposure(exposureIdx).rBFI = ...
        selected.byExposure(exposureIdx).rBFI(:,channelIdx);
    selected.byExposure(exposureIdx).meanIntensity = ...
        selected.byExposure(exposureIdx).meanIntensity(:,channelIdx);
end
end

function localPlotExposureResults(results,recName,recSavePrefix,stdStr,isMultipleExposure)
nChannels = size(results.byExposure(1).meanIntensity,2);
for exposureIdx = 1:numel(results.byExposure)
    exposureResult = results.byExposure(exposureIdx);
    exposureLabel = localExposureFileLabel(exposureResult.exposureTimeUs);
    if isMultipleExposure
        fileSuffix = ['_exp' exposureLabel 'us'];
    else
        fileSuffix = '';
    end
    figureTitle = sprintf('%s; exposure %.12g us',recName,exposureResult.exposureTimeUs);
    nColumns = 3;

    rawFigure = figure('Name',['SCOS Raw ' figureTitle], ...
        'Units','Normalized','Position',[0.01,1-0.16-nChannels*0.15,0.9,0.05+nChannels*0.15]);
    correctedFigure = figure('Name',['SCOS Corr ' figureTitle], ...
        'Units','Normalized','Position',[0.01,1-0.16-nChannels*0.15,0.9,0.05+nChannels*0.15]);

    for channelIdx = 1:nChannels
        rawSNR = NaN; rawFFT = []; rawFrequency = [];
        corrSNR = NaN; corrFFT = []; corrFrequency = [];
        if numel(exposureResult.timeVec) >= 3 && ...
                isfinite(exposureResult.effectiveFrameRateHz) && ...
                exposureResult.effectiveFrameRateHz > 0
            try
                [rawSNR,rawFFT,rawFrequency] = CalcSNR_Pulse( ...
                    exposureResult.rawSpeckleContrast(:,channelIdx), ...
                    exposureResult.effectiveFrameRateHz,false);
                [corrSNR,corrFFT,corrFrequency] = CalcSNR_Pulse( ...
                    exposureResult.corrSpeckleContrast(:,channelIdx), ...
                    exposureResult.effectiveFrameRateHz,false);
            catch err
                warning('SCOSNIRSvsTime:ExposureFFT','Exposure %.12g us FFT skipped: %s', ...
                    exposureResult.exposureTimeUs,err.message);
            end
        end

        figure(rawFigure);
        subplot(nChannels,nColumns,nColumns*(channelIdx-1)+1);
        plot(exposureResult.timeVec,exposureResult.meanIntensity(:,channelIdx));
        title(sprintf('Ch%d - mean I',channelIdx)); xlabel('Time [s]');
        subplot(nChannels,nColumns,nColumns*(channelIdx-1)+2);
        plot(exposureResult.timeVec,exposureResult.rawSpeckleContrast(:,channelIdx));
        title(sprintf('Ch%d - Raw',channelIdx)); xlabel('Time [s]');
        subplot(nChannels,nColumns,nColumns*(channelIdx-1)+3);
        if isempty(rawFrequency)
            axis off; text(0.1,0.5,'FFT unavailable');
        else
            plot(rawFrequency,rawFFT); title(sprintf('FFT: SNR=%.2g',rawSNR)); xlabel('Frequency [Hz]');
        end

        figure(correctedFigure);
        subplot(nChannels,nColumns,nColumns*(channelIdx-1)+1);
        plot(exposureResult.timeVec,exposureResult.meanIntensity(:,channelIdx));
        title(sprintf('Ch%d - mean I',channelIdx)); xlabel('Time [s]');
        subplot(nChannels,nColumns,nColumns*(channelIdx-1)+2);
        plot(exposureResult.timeVec,exposureResult.corrSpeckleContrast(:,channelIdx));
        title(sprintf('Ch%d - Corr',channelIdx)); xlabel('Time [s]');
        subplot(nChannels,nColumns,nColumns*(channelIdx-1)+3);
        if isempty(corrFrequency)
            axis off; text(0.1,0.5,'FFT unavailable');
        else
            plot(corrFrequency,corrFFT); title(sprintf('FFT: SNR=%.2g',corrSNR)); xlabel('Frequency [Hz]');
        end

        if any(exposureResult.corrSpeckleContrast(:,channelIdx) < 0)
            warning('SCOSNIRSvsTime:NegativeContrast', ...
                'Exposure %.12g us channel %d contains negative corrected contrast.', ...
                exposureResult.exposureTimeUs,channelIdx);
        end

        if exposureResult.timeVec(end) > 120
            timeToPlot = exposureResult.timeVec / 60;
            xLabel = 'time [min]';
        else
            timeToPlot = exposureResult.timeVec;
            xLabel = 'time [sec]';
        end
        relativeFigure = figure('Name',sprintf('rBFI Ch%d: %s',channelIdx,figureTitle), ...
            'Units','Normalized','Position',[0.1,0.1,0.4,0.4]);
        subplot(2,1,1);
        plot(timeToPlot,exposureResult.rBFI(:,channelIdx));
        xlabel(xLabel); ylabel('rBFI'); title(figureTitle,'Interpreter','none'); grid on;
        subplot(2,1,2);
        plot(timeToPlot,exposureResult.meanIntensity(:,channelIdx));
        xlabel(xLabel); ylabel('<I> [DU]'); grid on;
        savefig(relativeFigure,[recSavePrefix sprintf('_rBFi_Ch%d%s.fig',channelIdx,fileSuffix)]);
    end
    savefig(rawFigure,[recSavePrefix 'Local' stdStr '_plot' fileSuffix '.fig']);
    savefig(correctedFigure,[recSavePrefix 'Local' stdStr '_plot_corrected' fileSuffix '.fig']);
end
end

function label = localExposureFileLabel(exposureTimeUs)
if ~isfinite(exposureTimeUs)
    label = 'unknown';
else
    label = regexprep(sprintf('%.12g',exposureTimeUs),'[^0-9A-Za-z]','p');
end
end

function localFinalizeNirsOutput(nirs,results,info,recName,backgroundName, ...
        windowSize,nirsOptions,calculationOptions,plotFlag)
if exist(recName,'dir') == 7
    outputDirectory = recName;
else
    outputDirectory = fileparts(recName);
end
if isempty(outputDirectory)
    outputDirectory = pwd;
end

saveOutput = localLogicalOption(nirsOptions,'saveOutput',true);
plotNirs = localLogicalOption(nirsOptions,'plotNirs',logical(plotFlag));
if saveOutput
    outputFile = fullfile(outputDirectory,'SCOSNIRS_output.mat');
    nirsOptionsForSave = calculationOptions;
    save(outputFile,'nirs','results','info','recName','backgroundName', ...
        'windowSize','nirsOptionsForSave','-v7.3');
    fprintf('[SCOS-NIRS] Saved %s\n',outputFile);
end
if plotNirs
    localPlotNirs(nirs,recName,outputDirectory);
end
end

function value = localLogicalOption(options,name,defaultValue)
if isfield(options,name) && ~isempty(options.(name))
    value = options.(name);
    if ~(islogical(value) && isscalar(value)) && ...
            ~(isnumeric(value) && isscalar(value) && isfinite(value) && ismember(value,[0 1]))
        error('SCOSNIRSvsTime:Option', ...
            'options.%s must be a scalar logical value.',name);
    end
    value = logical(value);
else
    value = logical(defaultValue);
end
end


function localPlotNirs(nirs,recName,outputDirectory)
if isempty(nirs.timeVec)
    return
end
timeToPlot = nirs.timeVec;
timeLabel = 'Time [s]';
if timeToPlot(end) - timeToPlot(1) > 120
    timeToPlot = timeToPlot ./ 60;
    timeLabel = 'Time [min]';
end

figureHandle = figure('Name',['SCOS-NIRS: ' char(recName)], ...
    'Units','normalized','Position',[0.1 0.08 0.65 0.78]);
subplot(4,1,1);
plot(timeToPlot,nirs.HbO,'DisplayName','HbO'); hold on;
plot(timeToPlot,nirs.HbR,'DisplayName','HbR');
ylabel('Hb [model units]'); legend('Location','best'); grid on;
title(char(recName),'Interpreter','none');

subplot(4,1,2);
plot(timeToPlot,nirs.StO2);
ylabel('StO2 [%]'); grid on;

subplot(4,1,3);
plot(timeToPlot,nirs.rOEF,'DisplayName','rOEF'); hold on;
plot(timeToPlot,nirs.rBFI,'DisplayName','rBFI');
ylabel('Relative'); legend('Location','best'); grid on;

subplot(4,1,4);
plot(timeToPlot,nirs.rMRO2);
ylabel('rMRO2'); xlabel(timeLabel); grid on;

figurePath = fullfile(outputDirectory,'SCOSNIRS_Hb_StO2_rOEF_rMRO2.fig');
savefig(figureHandle,figurePath);
try
    exportgraphics(figureHandle, ...
        fullfile(outputDirectory,'SCOSNIRS_Hb_StO2_rOEF_rMRO2.png'));
catch exportError
    warning('SCOSNIRSvsTime:PlotExport','PNG export failed: %s',exportError.message);
end
end

function nirs = localCalculateNirsFromScosResults(results,options)
%LOCALCALCULATENIRS Calculate two-wavelength NIRS and CMRO2 surrogates.
%   NIRS = CALCULATENIRSFROMSCOSRESULTS(RESULTS,OPTIONS) consumes the
%   exposure-separated RESULTS produced earlier in this standalone function.
%   Wavelength frames are selected with saved Sequencer Set IDs, never frame
%   parity. Two source-detector ROI channels provide the spatial attenuation
%   slope for each wavelength.
%
%   Important OPTIONS fields (defaults shown):
%     wavelengthsNm             [785 830]
%     wavelengthSetIds          [0 1] when available
%     sourceDetectorChannels    [1 2]   % short, long ROI columns
%     sourceDetectorDistancesCm [2 3]
%     extinctionMatrix          [0.08 0.10; 0.11 0.08]
%     baselineDurationS         60
%     pairingToleranceS         []      % inferred from timestamps
%
%   HbO/HbR units follow the supplied extinction matrix. The defaults mirror
%   the legacy SCOS-NIRS calculation and must be replaced by calibrated
%   coefficients before interpreting concentrations quantitatively.

if nargin < 2 || isempty(options)
    options = struct();
end
if ~isstruct(options) || ~isscalar(options)
    error('CalculateNirsFromScosResults:Options', ...
        'options must be a scalar structure.');
end

options = localApplyDefaults(options);
localValidateOptions(options);
frames = localFlattenResults(results);

observedSetIds = unique(frames.sequencerSetId( ...
    isfinite(frames.sequencerSetId) & frames.sequencerSetId >= 0));
if isempty(options.wavelengthSetIds)
    if all(ismember([0;1],observedSetIds))
        wavelengthSetIds = [0 1];
        mappingMessage = ['wavelengthSetIds was not specified; assuming Set 0 = ' ...
            'first wavelength and Set 1 = second wavelength.'];
    elseif numel(observedSetIds) == 2
        wavelengthSetIds = reshape(sort(observedSetIds),1,2);
        mappingMessage = sprintf( ...
            'wavelengthSetIds was inferred as [%g %g] from the two observed Set IDs.', ...
            wavelengthSetIds(1),wavelengthSetIds(2));
    else
        error('CalculateNirsFromScosResults:WavelengthMapping', ...
            ['Unable to infer two wavelength states from Sequencer Set IDs. ' ...
             'Specify options.wavelengthSetIds = [setForLambda1 setForLambda2].']);
    end
    warning('CalculateNirsFromScosResults:AssumedWavelengthMapping','%s',mappingMessage);
else
    wavelengthSetIds = reshape(double(options.wavelengthSetIds),1,2);
    mappingMessage = sprintf('Explicit mapping: Set %g = %g nm, Set %g = %g nm.', ...
        wavelengthSetIds(1),options.wavelengthsNm(1), ...
        wavelengthSetIds(2),options.wavelengthsNm(2));
end

stateRows = cell(1,2);
for wavelengthIdx = 1:2
    stateRows{wavelengthIdx} = find(frames.sequencerSetId == wavelengthSetIds(wavelengthIdx));
    if isempty(stateRows{wavelengthIdx})
        error('CalculateNirsFromScosResults:MissingWavelengthFrames', ...
            'No analyzed frames have Sequencer Set ID %g.',wavelengthSetIds(wavelengthIdx));
    end
end

% Sequencer sets advance in ascending ID order. Pair the lower-ID state with
% the higher-ID state inside the same cycle, then restore wavelength order.
if wavelengthSetIds(1) < wavelengthSetIds(2)
    firstWavelengthIdx = 1;
    secondWavelengthIdx = 2;
else
    firstWavelengthIdx = 2;
    secondWavelengthIdx = 1;
end
firstRows = stateRows{firstWavelengthIdx};
secondRows = stateRows{secondWavelengthIdx};
[firstPairPositions,secondPairPositions,pairingToleranceS] = localPairCycles( ...
    frames.frameIndex(firstRows),frames.timeVec(firstRows), ...
    frames.frameIndex(secondRows),frames.timeVec(secondRows), ...
    options.pairingToleranceS);
if isempty(firstPairPositions)
    error('CalculateNirsFromScosResults:NoPairs', ...
        'No timestamp-consistent wavelength pairs were found.');
end

pairedRows = nan(numel(firstPairPositions),2);
pairedRows(:,firstWavelengthIdx) = firstRows(firstPairPositions);
pairedRows(:,secondWavelengthIdx) = secondRows(secondPairPositions);
pairedRows = round(pairedRows);

shortChannel = options.sourceDetectorChannels(1);
longChannel = options.sourceDetectorChannels(2);
if size(frames.meanIntensity,2) < max(options.sourceDetectorChannels)
    error('CalculateNirsFromScosResults:ChannelCount', ...
        ['SCOS results contain %d ROI channel(s), but sourceDetectorChannels ' ...
         'requests channel %d.'],size(frames.meanIntensity,2),max(options.sourceDetectorChannels));
end

nPairs = size(pairedRows,1);
intensityShort = nan(nPairs,2);
intensityLong = nan(nPairs,2);
bfiByWavelength = nan(nPairs,2);
actualExposureTimesUs = nan(nPairs,2);
frameIndices = nan(nPairs,2);
frameTimes = nan(nPairs,2);
for wavelengthIdx = 1:2
    rows = pairedRows(:,wavelengthIdx);
    intensityShort(:,wavelengthIdx) = frames.meanIntensity(rows,shortChannel);
    intensityLong(:,wavelengthIdx) = frames.meanIntensity(rows,longChannel);
    bfiByWavelength(:,wavelengthIdx) = frames.BFI(rows,longChannel);
    actualExposureTimesUs(:,wavelengthIdx) = frames.exposureTimeUs(rows);
    frameIndices(:,wavelengthIdx) = frames.frameIndex(rows);
    frameTimes(:,wavelengthIdx) = frames.timeVec(rows);
end
timeVec = mean(frameTimes,2);

validIntensityMask = all(isfinite(intensityShort) & intensityShort > 0 & ...
    isfinite(intensityLong) & intensityLong > 0,2);
if ~all(validIntensityMask)
    warning('CalculateNirsFromScosResults:InvalidIntensity', ...
        '%d wavelength pair(s) contain nonpositive or nonfinite intensity and return NaN.', ...
        nnz(~validIntensityMask));
end
if ~any(validIntensityMask)
    error('CalculateNirsFromScosResults:NoValidIntensity', ...
        'No wavelength pair has finite positive short- and long-distance intensity.');
end

distanceDifferenceMm = diff(options.sourceDetectorDistancesCm) * 10;
attenuationSlopePerMm = nan(nPairs,2);
attenuationSlopePerMm(validIntensityMask,:) = ...
    (log10(intensityShort(validIntensityMask,:)) - ...
     log10(intensityLong(validIntensityMask,:))) ./ distanceDifferenceMm;

reducedScatteringPerMm = options.reducedScatteringIntercept - ...
    options.reducedScatteringSlopePerNm .* options.wavelengthsNm;
muAperMm = nan(nPairs,2);
shortDistanceMm = options.sourceDetectorDistancesCm(1) * 10;
for wavelengthIdx = 1:2
    term = log(10) .* attenuationSlopePerMm(:,wavelengthIdx) - 2 / shortDistanceMm;
    muAperMm(:,wavelengthIdx) = term.^2 ./ (3 * reducedScatteringPerMm(wavelengthIdx));
end

hemoglobin = nan(nPairs,2);
hemoglobin(validIntensityMask,:) = ...
    (options.extinctionMatrix \ muAperMm(validIntensityMask,:).').';
HbO = hemoglobin(:,1);
HbR = hemoglobin(:,2);
denominator = HbO + HbR;
StO2 = 100 .* HbO ./ denominator;
StO2(~isfinite(StO2) | abs(denominator) <= eps) = NaN;
OEF = 1 - StO2 ./ 100;

baselineMask = timeVec <= timeVec(1) + options.baselineDurationS;
baselineOEF = localFiniteMean(OEF(baselineMask));
if ~isfinite(baselineOEF) || abs(baselineOEF) <= eps
    warning('CalculateNirsFromScosResults:InvalidOefBaseline', ...
        'The baseline OEF is invalid; rOEF and rMRO2 return NaN.');
    rOEF = nan(size(OEF));
else
    rOEF = OEF ./ baselineOEF;
end

bfiByWavelength(~isfinite(bfiByWavelength) | bfiByWavelength <= 0) = NaN;
combinedBFI = mean(bfiByWavelength,2,'omitnan');
combinedBFI(all(isnan(bfiByWavelength),2)) = NaN;
baselineBFI = localFiniteMean(combinedBFI(baselineMask));
if ~isfinite(baselineBFI) || baselineBFI <= 0
    warning('CalculateNirsFromScosResults:InvalidBfiBaseline', ...
        'The baseline BFI is invalid; rBFI and rMRO2 return NaN.');
    rBFI = nan(size(combinedBFI));
else
    rBFI = combinedBFI ./ baselineBFI;
end
rMRO2 = rOEF .* rBFI;

nirs = struct();
nirs.timeVec = timeVec;
nirs.frameTimes = frameTimes;
nirs.frameIndices = frameIndices;
nirs.pairTimeDifferenceS = abs(diff(frameTimes,1,2));
nirs.pairingToleranceS = pairingToleranceS;
nirs.wavelengthsNm = reshape(options.wavelengthsNm,1,2);
nirs.wavelengthSetIds = wavelengthSetIds;
nirs.wavelengthMapping = mappingMessage;
nirs.sourceDetectorChannels = reshape(options.sourceDetectorChannels,1,2);
nirs.sourceDetectorDistancesCm = reshape(options.sourceDetectorDistancesCm,1,2);
nirs.intensityShort = intensityShort;
nirs.intensityLong = intensityLong;
nirs.actualExposureTimesUs = actualExposureTimesUs;
nirs.attenuationSlopePerMm = attenuationSlopePerMm;
nirs.reducedScatteringPerMm = reducedScatteringPerMm;
nirs.muAperMm = muAperMm;
nirs.extinctionMatrix = options.extinctionMatrix;
nirs.HbO = HbO;
nirs.HbR = HbR;
nirs.StO2 = StO2;
nirs.OEF = OEF;
nirs.rOEF = rOEF;
nirs.BFIByWavelength = bfiByWavelength;
nirs.BFI = combinedBFI;
nirs.rBFI = rBFI;
nirs.rMRO2 = rMRO2;
nirs.baselineMask = baselineMask;
nirs.baselineDurationS = options.baselineDurationS;
nirs.baselineOEF = baselineOEF;
nirs.baselineBFI = baselineBFI;
nirs.validPairMask = validIntensityMask;
nirs.options = options;
nirs.modelNote = ['Spatially resolved two-distance model. HbO/HbR units depend on ' ...
    'the supplied extinction matrix; rOEF and rMRO2 are baseline-relative surrogates.'];
end


function options = localApplyDefaults(options)
defaults = struct( ...
    'wavelengthsNm',[785 830], ...
    'wavelengthSetIds',[], ...
    'sourceDetectorChannels',[1 2], ...
    'sourceDetectorDistancesCm',[2 3], ...
    'extinctionMatrix',[0.08 0.10; 0.11 0.08], ...
    'baselineDurationS',60, ...
    'pairingToleranceS',[], ...
    'reducedScatteringIntercept',1, ...
    'reducedScatteringSlopePerNm',5.9e-4);
names = fieldnames(defaults);
for idx = 1:numel(names)
    if ~isfield(options,names{idx}) || isempty(options.(names{idx}))
        options.(names{idx}) = defaults.(names{idx});
    end
end
end


function localValidateOptions(options)
validateattributes(options.wavelengthsNm,{'numeric'},{'real','finite','positive','numel',2});
if ~isempty(options.wavelengthSetIds)
    validateattributes(options.wavelengthSetIds,{'numeric'}, ...
        {'real','finite','integer','nonnegative','numel',2});
    if options.wavelengthSetIds(1) == options.wavelengthSetIds(2)
        error('CalculateNirsFromScosResults:WavelengthSetIds', ...
            'wavelengthSetIds must contain two different Set IDs.');
    end
end
validateattributes(options.sourceDetectorChannels,{'numeric'}, ...
    {'real','finite','integer','positive','numel',2});
if options.sourceDetectorChannels(1) == options.sourceDetectorChannels(2)
    error('CalculateNirsFromScosResults:Channels', ...
        'sourceDetectorChannels must contain different short and long ROI channels.');
end
validateattributes(options.sourceDetectorDistancesCm,{'numeric'}, ...
    {'real','finite','positive','numel',2});
if options.sourceDetectorDistancesCm(2) <= options.sourceDetectorDistancesCm(1)
    error('CalculateNirsFromScosResults:Distances', ...
        'sourceDetectorDistancesCm must be [short long] with long > short.');
end
validateattributes(options.extinctionMatrix,{'numeric'},{'real','finite','size',[2 2]});
if rcond(double(options.extinctionMatrix)) <= eps
    error('CalculateNirsFromScosResults:ExtinctionMatrix', ...
        'extinctionMatrix must be nonsingular.');
end
validateattributes(options.baselineDurationS,{'numeric'}, ...
    {'real','finite','positive','scalar'});
if ~isempty(options.pairingToleranceS)
    validateattributes(options.pairingToleranceS,{'numeric'}, ...
        {'real','finite','positive','scalar'});
end
validateattributes(options.reducedScatteringIntercept,{'numeric'}, ...
    {'real','finite','scalar'});
validateattributes(options.reducedScatteringSlopePerNm,{'numeric'}, ...
    {'real','finite','nonnegative','scalar'});
reducedScattering = options.reducedScatteringIntercept - ...
    options.reducedScatteringSlopePerNm .* options.wavelengthsNm;
if any(reducedScattering <= 0)
    error('CalculateNirsFromScosResults:ReducedScattering', ...
        'The reduced-scattering model must stay positive at both wavelengths.');
end
end


function frames = localFlattenResults(results)
if ~isstruct(results) || ~isfield(results,'byExposure') || isempty(results.byExposure)
    error('CalculateNirsFromScosResults:Results', ...
        'results.byExposure from SCOS analysis is required.');
end

frameIndex = [];
timeVec = [];
sequencerSetId = [];
exposureTimeUs = [];
meanIntensity = [];
BFI = [];
nChannels = [];
for exposureIdx = 1:numel(results.byExposure)
    series = results.byExposure(exposureIdx);
    required = {'frameIndices','timeVec','meanIntensity','BFI'};
    for fieldIdx = 1:numel(required)
        if ~isfield(series,required{fieldIdx})
            error('CalculateNirsFromScosResults:ResultsField', ...
                'results.byExposure(%d).%s is required.',exposureIdx,required{fieldIdx});
        end
    end
    count = numel(series.frameIndices);
    if size(series.meanIntensity,1) ~= count || size(series.BFI,1) ~= count || ...
            numel(series.timeVec) ~= count
        error('CalculateNirsFromScosResults:ResultsLength', ...
            'SCOS result arrays have inconsistent lengths in exposure group %d.',exposureIdx);
    end
    if isempty(nChannels)
        nChannels = size(series.meanIntensity,2);
    elseif size(series.meanIntensity,2) ~= nChannels || size(series.BFI,2) ~= nChannels
        error('CalculateNirsFromScosResults:ResultsChannels', ...
            'SCOS exposure groups have inconsistent ROI channel counts.');
    end

    if isfield(series,'sequencerSetIds') && ~isempty(series.sequencerSetIds)
        setIds = double(series.sequencerSetIds(:));
        if numel(setIds) ~= count
            error('CalculateNirsFromScosResults:SetIdLength', ...
                'sequencerSetIds length differs from frame count in exposure group %d.',exposureIdx);
        end
    else
        setIds = nan(count,1);
    end
    if isfield(series,'actualExposureTimesUs') && ~isempty(series.actualExposureTimesUs)
        exposure = double(series.actualExposureTimesUs(:));
        if numel(exposure) ~= count
            error('CalculateNirsFromScosResults:ExposureLength', ...
                'actualExposureTimesUs length differs from frame count in exposure group %d.',exposureIdx);
        end
    elseif isfield(series,'exposureTimeUs') && isscalar(series.exposureTimeUs)
        exposure = repmat(double(series.exposureTimeUs),count,1);
    else
        exposure = nan(count,1);
    end

    frameIndex = [frameIndex; double(series.frameIndices(:))]; %#ok<AGROW>
    timeVec = [timeVec; double(series.timeVec(:))]; %#ok<AGROW>
    sequencerSetId = [sequencerSetId; setIds]; %#ok<AGROW>
    exposureTimeUs = [exposureTimeUs; exposure]; %#ok<AGROW>
    meanIntensity = [meanIntensity; double(series.meanIntensity)]; %#ok<AGROW>
    BFI = [BFI; double(series.BFI)]; %#ok<AGROW>
end

if any(~isfinite(frameIndex)) || any(frameIndex < 1) || any(frameIndex ~= round(frameIndex)) || ...
        numel(unique(frameIndex)) ~= numel(frameIndex)
    error('CalculateNirsFromScosResults:FrameIndices', ...
        'frameIndices must be unique positive 1-based integers.');
end
if any(~isfinite(timeVec))
    error('CalculateNirsFromScosResults:Timestamps', ...
        'Finite camera-derived or fallback timestamps are required for wavelength pairing.');
end
[frameIndex,order] = sort(frameIndex);
timeVec = timeVec(order);
if any(diff(timeVec) <= 0)
    error('CalculateNirsFromScosResults:Timestamps', ...
        'SCOS frame timestamps must be strictly increasing in frame order.');
end
frames = struct( ...
    'frameIndex',frameIndex, ...
    'timeVec',timeVec, ...
    'sequencerSetId',sequencerSetId(order), ...
    'exposureTimeUs',exposureTimeUs(order), ...
    'meanIntensity',meanIntensity(order,:), ...
    'BFI',BFI(order,:));
end


function [firstPositions,secondPositions,toleranceS] = localPairCycles( ...
        firstFrameIndices,firstTimes,secondFrameIndices,secondTimes,requestedToleranceS)
if isempty(requestedToleranceS)
    periods = [];
    if numel(firstTimes) > 1
        periods(end+1) = median(diff(firstTimes));
    end
    if numel(secondTimes) > 1
        periods(end+1) = median(diff(secondTimes));
    end
    periods = periods(isfinite(periods) & periods > 0);
    if isempty(periods)
        toleranceS = inf;
    else
        toleranceS = 1.05 * min(periods);
    end
else
    toleranceS = double(requestedToleranceS);
end

firstPositions = zeros(0,1);
secondPositions = zeros(0,1);
secondIdx = 1;
for firstIdx = 1:numel(firstFrameIndices)
    while secondIdx <= numel(secondFrameIndices) && ...
            secondFrameIndices(secondIdx) < firstFrameIndices(firstIdx)
        secondIdx = secondIdx + 1;
    end
    if secondIdx > numel(secondFrameIndices)
        break
    end
    if firstIdx < numel(firstFrameIndices)
        nextFirstFrame = firstFrameIndices(firstIdx+1);
    else
        nextFirstFrame = inf;
    end
    if secondFrameIndices(secondIdx) >= nextFirstFrame
        continue
    end
    timeDifference = secondTimes(secondIdx) - firstTimes(firstIdx);
    if timeDifference >= 0 && timeDifference <= toleranceS + eps(max(abs(secondTimes(secondIdx)),1))
        firstPositions(end+1,1) = firstIdx; %#ok<AGROW>
        secondPositions(end+1,1) = secondIdx; %#ok<AGROW>
    end
    secondIdx = secondIdx + 1;
end
end


function value = localFiniteMean(values)
values = values(isfinite(values));
if isempty(values)
    value = NaN;
else
    value = mean(values);
end
end
