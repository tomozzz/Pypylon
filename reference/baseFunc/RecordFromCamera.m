%% [ rec, recName , info ] = RecordFromCamera ( nOfFrames, camParams, setupParams, folder, saveFormat, prefix, suffix, overwriteFlag, plotFlag, vid )
% Input : 
%   nOfFrames - desired number of frames. default = 1

%   folder - folder to which file should be saved. The parent folder should exist.
%            if not passed of is empty , record will not be saved.
%            Name of the file will contain all the parameters.
%   saveFormat - '.avi' or '.tiff' .  default = '.tiff'
%                in case of .mat format, the file will start with 'Rec_' prefix
%   camParams - camera parameters such as exposureTime, Gain, BlackLevel and etc..
%               Note that the names must follow the camera strtuct src=getselectedsource(vid)
%               Any parameter that does not appear - the previously defined value will be used.
%               Special parameter is 'videoFormat', which is not src field but vid field.
%               If field named 'addToFilename' appeares and it is false, the camParams won't be used in filename.
%               If addToFilename is struct -> it should contain the fields
%               as cameraParams that are equal to true or false. If
%               parameter is abscent - it's default is true
%               
%
%   setupParams - setup parameters such as laserPower, Lensf, Objective and etc..
%               Used for metadata and for record name construction.
%               If field named 'addToFilename' appeares and it is false, the setupParams won't be used in filename
%   prefix - prefix for the filname
%   suffix - suffix for the filname 
%   videoFormat - "Mono8" or "Mono12" ( for additional formats - need to update the code )
%   overwriteFlag  - save recording even if recording with the same name already exists
%   plotFlag  - plot last frame of the record. default = true
%               can also be a handle to a figure ( in which you want to plot the image)
%   vid       - preopened video object. Not very recommended for use.

%   * metadata is saved automatically in .mat file in variables called 'cam' and 'setup' 
%     in 'cam' {'ExposureTime','AcquisitionFrameRate','BlackLevel','Gain'} fields always saved, in addition to what appears in camParams
%     in 'setup' equals to  setupParams excluding 'addToFilename' field
%     for '.tiff' format - inside 'folder', file named 'info.mat'
%     for '.avi' format  - inside 'folder', the same name as the recording, but adeed '_info.mat' suffix instead of '.avi'
%
%   * any of the input parameters can be empty. 
% Output :
%   rec      - 3D matrix, double
%   recName - output full record name (file/folder including path)
% ``````````````````````````````````````````````````````````````````````````````````````````````````````````````````````````````````

function [ rec, recName, info ] = RecordFromCamera( nOfFrames, camParams, setupParams, folder, saveFormat, prefix, suffix, overwriteFlag, plotFlag, vid , beepInterval)

%% Check functin input parameters and set defualt values for missing parameters

if ~exist('nOfFrames','var') || isempty(nOfFrames)
    nOfFrames = 1;
end
 
if ~exist('camParams','var') || isempty(camParams)
    camParams = struct();
elseif ~isstruct(camParams)
    error('camParams shold be a struct!')
end

if ~exist('setupParams','var') || isempty(setupParams)
    setupParams = struct();
elseif ~isstruct(setupParams)
    error('setupParams shold be a struct!')
end

if ~exist('prefix','var')
    prefix = '';
end

if ~exist('suffix','var') 
    suffix = '';
elseif ~isempty(suffix)
    suffix=['_' suffix];
end

if ~exist('saveFormat','var') || isempty(saveFormat)
    saveFormat = '.tiff';
end

if ~exist('forceWrite','var') || isempty(overwriteFlag)
    overwriteFlag = false;
end

if ~exist('plotFlag','var') || isempty(plotFlag)
    plotFlag = true;
    figHandle = figure('name','Record Image');
else
    if isequal(plotFlag,true)
        figHandle = figure('name','Record Image');
    elseif isequal(plotFlag,false)
        % do nothing
    elseif isgraphics(plotFlag,'figure')
        figHandle =  plotFlag;
        plotFlag = true;
    else 
        error('Wrong input for plotFlag - must be true/false or a figure handle')
    end
end

% check existance of parent folder
if exist('folder','var') && ~isempty(folder) 
    if isequal(folder,0) 
        error('Input folder must not be zero!');
    elseif ~ischar(folder) && ~isstring(folder)
        error('Input folder must be a char array or a string');
    elseif  exist(fileparts(folder),'dir') ~= 7
        error('The parent folder of the destination folder must exist');
    end
end

if ~exist('folder','var') || isempty(folder)
    recName = '';
end

createVid= ~exist('vid','var') || isempty(vid);

%% Create vid and set Camera parameters
if ~isfield(camParams,'videoFormat') 
    if ~createVid
        videoFormat = vid.VideoFormat;
        if ~ismember({'Mono8','Mono12'},videoFormat)
            error(['Unexpected video format "' videoFormat '"']);
        end
    else
        videoFormat = 'Mono8';
    end
elseif ~ismember({'Mono8','Mono12'},camParams.videoFormat)
    error(['Video format "' camParams.videoFormat '" is not supported. Must be "Mono8" or "Mono10"'])
elseif strcmp(camParams.videoFormat,'Mono12') && strcmp(saveFormat,'.avi')
    error('Saving Mono12 in .avi format is not possible');
else
    videoFormat = camParams.videoFormat;
end

if createVid
    vid = videoinput("gentl", 1, videoFormat);
end

vid.FramesPerTrigger = Inf; 
src = getselectedsource(vid);

camInputFields = fieldnames(camParams); 
camInputFields(ismember(camInputFields,{'addToFilename','videoFormat'})) = [];
camOriginalFields = fieldnames(src);
if ~all(ismember(camInputFields,camOriginalFields))
    disp('camera src struct fields : ')
    disp(camOriginalFields)
    badFields = strjoin(camInputFields(~ismember(camInputFields,camOriginalFields)));
    delete(vid)
    error(['camParams should have only legit fields for camera src struct. The following field are not exceptable :' badFields ])
end

% set camera parameters
if ( isfield(camParams,'TriggerMode') &&  strcmpi(camParams.TriggerMode,'On') ) || strcmpi(src.TriggerMode,'On')
    triggerconfig(vid, 'hardware');
end

if ~isempty(camInputFields)
    for field = camInputFields(:)'
        if strcmp(field{1},'addToFilename'); continue; end
        if ischar(camParams.(field{1}))
             fprintf('Setting %s = %s\n',field{1},camParams.(field{1}));
        else
            fprintf('Setting %s = %g\n',field{1},camParams.(field{1}));
        end
        src.(field{1}) = camParams.(field{1});  
    end    

    if isfield(camParams,'AcquisitionFrameRate') 
         src.AcquisitionFrameRateEnable = 'True'; 
    end
end

%% Create filename from Parameters Structs
if exist('folder','var') && ~isempty(folder)
    [recName, recName] = GenerateFileName(folder,camParams,setupParams,prefix,suffix,saveFormat,overwriteFlag,src);
else
    [~, recName] = GenerateFileName('',camParams,setupParams,prefix,suffix,'.tiff',1,src);
end

%% Create info struct
if isfield(camParams,'addToFilename'); camParams = rmfield(camParams,'addToFilename'); end
if isfield(setupParams,'addToFilename'); setupParams = rmfield(setupParams,'addToFilename'); end

info.cam = camParams; % TBD consider using only user requested + expT,Gain,FR,BL
mustFieldsToSave = {'Gain','ExposureTime','BlackLevel','AcquisitionFrameRate','DeviceSerialNumber'} ;
for field = mustFieldsToSave(:)'
    if ~isfield(camParams,field{1})
        info.cam.(field{1})= src.(field{1});
    end
end
info.setup = setupParams;
info.cameraSN = src.DeviceSerialNumber;
info.cameraVendor = src.DeviceVendorName;
info.cameraModel = src.DeviceModelName;
%% Get images Sequence from Camera
if exist('folder','var') && ~isempty(folder)
    fprintf('Recording "%s" ... \n',recName);
end
start(vid);

%allocate 
while(~vid.FramesAvailable); pause(0.001); end
imagesBuff = getdata(vid, vid.FramesAvailable); 
rec = zeros(size(imagesBuff,1),size(imagesBuff,2),nOfFrames);
if strcmp(videoFormat,'Mono8')
    rec = uint8(rec);
elseif strcmp(videoFormat,'Mono12')
    rec = uint16(rec);
end

% Start aquisition
k=1;
h_waitbar = waitbar(0,'Recording ...');

%Sound Setting
fs = 44100; % Sampling frequency (Hz)
t = 0:1/fs:1; % Time vector (1 second)
freq = [700,400]; % Frequency of the sine wave (Hz)
amplitude = 0.4; % Amplitude of the sine wave
freq_i = 3;
beepFlag = exist('beepInterval','var');
while k <= nOfFrames 
        %currImage = getsnapshot(v);
        if vid.FramesAvailable
            if mod(k,10)==0; fprintf('%d\t',k); end
            if mod(k,100) == 0; fprintf('\n'); end
                
            currImagesBuff = getdata(vid, vid.FramesAvailable);
            buffSize = size(currImagesBuff,4);
            if strcmp(videoFormat,'Mono8')
                currImage = uint8(squeeze(currImagesBuff));
            elseif strcmp(videoFormat,'Mono12')
                currImage = uint16(squeeze(currImagesBuff));
            end            
            rec(:,:,k:k+buffSize-1) = currImage;
            
            if mod(k,10)==0 
                waitbar(k/nOfFrames,h_waitbar,['Recording frame ' num2str(k)]);
            end
            
            if beepFlag && mod(k,beepInterval)==0               
                sound(amplitude * sin(2*pi*freq(freq_i)*t), fs);
                freq_i = freq_i + 1;
                if freq_i >  length(freq); freq_i=1; end
            end
            k = k + buffSize;
        end
end
fprintf('\n');
%disp(['src.AcquisitionFrameRate = ' num2str(src.AcquisitionFrameRate)] );

stop(vid);
if createVid; delete(vid); end

% delete extra frames
if size(rec,3) > nOfFrames 
    rec(:,:,nOfFrames+1:end) = [];
end

waitbar(k/nOfFrames,h_waitbar,'Saving...');
%% Plot
if plotFlag
    
    set(figHandle,'name',recName);
    figure(figHandle);
    imagesc(rec(:,:,end)); colormap gray;
    axis equal
    imageAx = gca;
    imageAx.XLim = [0 size(rec,2)];
    imageAx.YLim = [0 size(rec,1)];
    title({recName ; sprintf('frame %d',size(rec,3))},'FontSize',10,'interpreter','none');
    colorbar;
end

%% Save Recording
if exist('folder','var') && ~isempty(folder)
    % -- create folder if needed
    if ~exist(folder,'dir')
        mkdir(folder);
    end    

    % -- Save
    disp(['Saving "' recName '" ...'])
    switch saveFormat
%         case '.mat'
%             save(filename,'rec');
%             save([filename(1:end-4) '_info'] ,'-struct','info');
        case '.tiff'
            WriteTiffSeq(recName,rec,videoFormat);
            save([recName '\info.mat'],'-struct','info');
%             prettyjson(info,[filename '\info.json']);
        case '.avi'
            WriteAvi(recName,rec,videoFormat,info.cam.AcquisitionFrameRate);
            save([recName '_info.mat'],'-struct','info');
%             prettyjson(info,[ filename '_info.json']);
        otherwise
            error('wrong saveFormat, must be .tiff or .mat. or .avi')
    end
    
    if nargout > 2
        info.name = GetParamsFromFileName(recName); 
    end
    
    rec = double(rec);
end
close(h_waitbar);
end 

function [fullName, recName] = GenerateFileName(folder,camParams,setupParams,prefix,suffix,saveFormat,forceWrite,src)
    mustFieldsForFilename = {'Gain','ExposureTime'};
    for field = mustFieldsForFilename(:)'
        if ~isfield(camParams,field{1})
            camParams.(field{1})= src.(field{1});
        end
    end
    camParamsStr   = Struct2String(camParams,CamParamsLUT());
    setupParamsStr = Struct2String(setupParams,SetupParamsLUT);
        
    recNameBase = sprintf('%s%s%s%s',prefix,setupParamsStr,camParamsStr,suffix);
    if isempty(recNameBase)
        error('Record name cannot be empty! Please specify prefix/suffix or enable parameters in the name');
    end
    if isempty(prefix) && recNameBase(1)=='_'
        recNameBase(1) = []; 
    end

    if forceWrite
        if exist([folder '\' recNameBase '.avi'],'file')
            delete([folder '\' recNameBase '.avi']);
        elseif exist([folder '\' recNameBase ],'file')                
            delete([folder '\' recNameBase ]);
        end
        recName = recNameBase;
    else
        pattern = [regexptranslate('escape', recNameBase), '_(\d+)(.avi)?$'];

        samefiles = dir([folder '\' recNameBase '_*']);
        if ~isempty(samefiles)
            samefiles = samefiles([samefiles.isdir] | cellfun(@(x) endsWith(x,',avi'), {samefiles.name} ,'UniformOutput',true)); % filter only folders and .avi files
            samefiles = { samefiles(cellfun(@(x) ~isempty(regexp(x, pattern,'once')), {samefiles.name} ,'UniformOutput',true)).name } ; % find files with the same name but different index
            filesIndices = [];
            for filename=samefiles(:)'
                match = regexp(filename{1}, pattern,'tokens');
                filesIndices = [ filesIndices, str2double(match{1}{1}) ]; %#ok<AGROW>
            end
            if isempty(filesIndices)
                newIndex = 0;
            else
                newIndex = max(filesIndices)+1;
            end
            if newIndex > 999
                error(['Too many records with the same name "' folder '\' recNameBase '"' ] );
            end
        else
            newIndex = 0;
        end
        newIndexStr = sprintf('%0*d',3,newIndex);
        recName = [recNameBase '_' newIndexStr];
    end
    if ismember(saveFormat,{'avi'})
        recName = [recName '.avi']; 
    end
    fullName = fullfile(folder,recName);
end

function  [lut, name_out , units ] = CamParamsLUT(name_in)
    % Create lut
    lut = { 'ExposureTime'          , 'expT'   , 'us' ;...
            'AcquisitionFrameRate'  , 'FR'     , 'Hz' ;...
            'BlackLevel'            , 'BL'     , 'DU' ;...
            'Gain'                  , 'Gain'   , 'dB' ;...
          };
    
    % Check lut first column uniqueness 
    if  numel(unique(lut(:,1))) ~= size(lut,1)
        error('Values in first column of CamParamsLut should be unique!')
    end
    
    % Extract param from lut  
    if nargin > 0
        ind = ismember(lut(:,1),name_in);
        if numel(ind) == 0
            name_out = name_in;
        elseif numel(ind) > 1
            error('Two identical entries in lut table');
        else
            name_out = lut(ind,2);
            units    = lut(ind,3);
        end
    else
        name_out = '';
        units = '';
    end
end

function  [lut, name_out, units ] = SetupParamsLUT(name_in)
    % Create lut
    lut = { 'Lens'                  , 'Lens'   , 'mm' ;...
            };
    
    % Check lut first column uniqueness 
    if  numel(unique(lut(:,1))) ~= size(lut,1)
        error('Values in first column of CamParamsLut should be unique!')
    end
    
    % Extract param from lut  
    if nargin > 0
        ind = ismember(lut(:,1),name_in);
        if numel(ind) == 0
            name_out = name_in;
        elseif numel(ind) > 1
            error('Two identical entries in lut table');
        else
            name_out = lut(ind,2);
            units    = lut(ind,3);
        end
    else
        name_out = '';
        units = '';
    end
end


