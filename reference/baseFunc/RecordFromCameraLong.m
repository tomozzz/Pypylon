function [ filename ] = RecordFromCameraLong(nOfFrames,Tint,gain,frameRate,blackLevel,outputParentFolder,prefix,suffix,vid,videoFormat)
%% ! DONT USE - NEEDS TO BE CHECKED
%% [ rec, filename ] = RecordFromCameraLong(nOfFrames,Tint,gain,frameRate,blackLevel,outputParentFolder,prefix,suffix,vid,videoFormat)
% Records from camera and saved the record in .tiff files - frame by frame
% Input : 
%   nOfFrames - desired number of frames. default = 1
%   Tint - integration (=exposure) time in ms
%   gain - analog camera gain in dB
%   frameRate - frames per second [Hz]
%   blackLevel - Offset of the image ( in [DU] ). For bester should be in range of [0,30]
%   outputParentFolder - folder in which new folder will be created and inside it .tiff files will be saved            
%   prefix - prefix for the filname
%   suffix - suffix for the filname 
%   vid    - preopened video object
%   videoFormat - "Mono8" or "Mono12" ( for additional formats - need to update the code )
%
%   * metadata is saved automatically in .mat file in variable called 'src' 
%     for '.mat' format  - inside the record matfile
%     for '.tiff' format - inside 'folder', file named 'src.mat'
%     for '.avi' format  - inside 'folder', the same name as the recording, but adeed '_src.mat' suffix instead of '.avi'
%
%   * any of the input parameters can be empty or missing, except 'folder'. In case of Tint,gain,frameRate,blackLevel - the parameters previously set to the camera are useed.
% Output :
%   filename - output folder full name (including path)
% ``````````````````````````````````````````````````````````````````````````````````````````````````````````````````````````````````

%% open video object and set record parameters into video object
createVid= ~exist('vid','var') || isempty(vid);
if ~exist('videoFormat','var') || isempty(videoFormat)
    if ~createVid
        videoFormat = vid.VideoFormat;
    else
        videoFormat = "Mono8";
    end
elseif ~ismember(videoFormat,{"Mono8","Mono10"})
    error(['Video format "' videoFormat '" is not supported. Must be "Mono8" or "Mono10"'])
end

if createVid
    vid = videoinput("gentl", 1, videoFormat);
    if exist('videoFormat','var') && ~isempty(videoFormat)
        errror('Input error : If vid is passed videoFormat should not be passed');
    end
end

src = getselectedsource(vid);
vid.FramesPerTrigger = Inf; 

if exist('Tint','var') && ~isempty(Tint)
    src.ExposureTime = Tint*1000;
end

if exist('gain','var') && ~isempty(gain)
    src.Gain = gain;
end

if exist('blackLevel','var') && ~isempty(blackLevel)
    src.BlackLevel = blackLevel;
end

if exist('frameRate','var') && ~isempty(frameRate)
    src.AcquisitionFrameRate = frameRate;
end

if ~exist('nOfFrames','var') || isempty(nOfFrames)
    nOfFrames = 1;
end

%% Create output folder if needed
if exist(fileparts(outputParentFolder),'dir') ~= 7
    error('The parent folder of the destination folder must exist');
end
if ~exist(outputParentFolder,'dir')
    mkdir(outputParentFolder);
end

% set recording name
recordName = sprintf("%sTint%gms_Gain%gdB_FR%gHz_BL%gDU%s",prefix,Tint,gain,frameRate,blackLevel,suffix);

% check that folder is empty
destFolder = fullfile(folder,recordName);
if exist(destFolder,'dir') == 7
    mkdir(destFolder)
elseif ~isempty(dir(fullfile(folder,recordName,'*.tiff')))
    error('some tiff recording already exist in this destination');
end

% prepare target struct :
% find the images size
start(vid);
while(~vid.FramesAvailable); pause(0.001); end
imageBuff = getdata(vid, 1); % try this
stop(vid)

tagstruct.ImageLength = size(imageBuff,1);
tagstruct.ImageWidth  = size(imageBuff,2);            
if strcmp(videoFormat,"Mono8")
    tagstruct.BitsPerSample = 8;
elseif strcmp(videoFormat,"Mono12")
    tagstruct.BitsPerSample = 12;
else 
    error('Unsupported format for writing .tiffs')
end
tagstruct.SamplesPerPixel = 1;
tagstruct.Software = 'MATLAB';
tagstruct.Photometric = Tiff.Photometric.MinIsBlack;
tagstruct.PlanarConfiguration = Tiff.PlanarConfiguration.Chunky;

% save parameters
save(fullfile(destFolder,'src.mat'),'src');

%% Start recording!
start(vid);
fig = figure;
imageAx = axes(fig); k=1;
while k <= nOfFrames 
    if vid.FramesAvailable
        fprintf('frame %d\n',k);

        % --- get frame from video buffer
        currImagesBuff = getdata(vid, vid.FramesAvailable);
%             size(currImagesBuff)
        currImage = squeeze(currImagesBuff(:,:,:,1));
        if strcmp(videoFormat,'Mono8')
            currImage = uint8(currImage);
        elseif strcmp(videoFormat,'Mono12')
            currImage = uint16(currImage);
        end
        
        % --- save image to .tiff
        t = Tiff([destFolder,sprintf('\\Frame%0*d.tiff',3,k)],'w');
        setTag(t,tagstruct);
        write(t,currImage);
        close(t);

        % --- show image in figure
        imagesc(currImage, 'Parent', imageAx); colormap gray; 
        %axis(0.5+[1,1,size(currImage,2),size(currImage,1)],'equal')
        axis equal
        title({sprintf('FPS=%.3g, Exposure=%.2gms, Gain=%.2gdB',frameRate,Tint,gain),sprintf('frame %d',k)})
        
        % --- increment index
        k = k + 1;
    end
end

stop(vid);

if createVid
    delete(vid)
end
    
filename = fullfile(outputParentFolder,raeFolderName);
end