function varargout = SCOS_GUI(varargin)
% SCOS_GUI MATLAB code for SCOS_GUI.fig
% Begin initialization code - DO NOT EDIT
gui_Singleton = 1;
gui_State = struct('gui_Name',       'SCOS_GUI', ...
                   'gui_Singleton',  gui_Singleton, ...
                   'gui_OpeningFcn', @SCOS_GUI_OpeningFcn, ...
                   'gui_OutputFcn',  @SCOS_GUI_OutputFcn, ...
                   'gui_LayoutFcn',  [] , ...
                   'gui_Callback',   []);
if nargin && ischar(varargin{1})
    gui_State.gui_Callback = str2func(varargin{1});
end

if nargout
    [varargout{1:nargout}] = gui_mainfcn(gui_State, varargin{:});
else
    gui_mainfcn(gui_State, varargin{:});
end
% End initialization code - DO NOT EDIT

% --- Init GUI ----- 
function SCOS_GUI_OpeningFcn(hObject, eventdata, handles, varargin)
% This function has no output args, see OutputFcn.
% hObject    handle to figure
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user data (see GUIDATA)
% varargin   command line arguments to SCOS_GUI (see VARARGIN)

% Choose default command line output for SCOS_GUI
handles.output = hObject;

% Update handles structure
guidata(hObject, handles);

% UIWAIT makes SCOS_GUI wait for user response (see UIRESUME)
% uiwait(handles.fig_SCOS_GUI);

% ============ Start Code ===================================
addpath([fileparts(fileparts(mfilename('fullpath'))) '\baseFunc']);
handles.tgl_startVideo.UserData.calcSCOS_Flag = false;
handles.tgl_startVideo.UserData.scosData = nan(1,10000);
handles.tgl_startVideo.UserData.scosTime = nan(1,10000);
handles.tgl_startVideo.UserData.resetSCOS_Flag = true;
handles.tgl_startVideo.UserData.calcSCOS_lastClock = 0;
handles.tgl_startVideo.UserData.calcSCOS_beforeVideoStop_Flag = false;
% handles.fig_SCOS_GUI.UserData.isVideoRunning = false;
handles.fig_SCOS_GUI.UserData.recFolder = [ fileparts(fileparts(mfilename('fullpath'))) '\Records\timeData' ];
if ~exist(handles.fig_SCOS_GUI.UserData.recFolder,'dir'); mkdir(handles.fig_SCOS_GUI.UserData.recFolder); end
recTimestamp = datestr(datetime('now'),'yyyy-mm-dd_HH-MM-SS');
handles.fig_SCOS_GUI.UserData.recName = fullfile(handles.fig_SCOS_GUI.UserData.recFolder, ['Rec_' recTimestamp '.mat']);
handles.tgl_startVideo.UserData.saveEachNframes = 200;

%------
handles.tgl_startVideo.UserData.calcSCOS_Flag = false;
handles.tgl_startVideo.UserData.scosData = nan(1,10000);
handles.tgl_startVideo.UserData.scosTime = nan(1,10000);
handles.tgl_startVideo.UserData.resetSCOS_Flag = true;
handles.tgl_startVideo.UserData.calcSCOS_lastClock = 0;
handles.tgl_startVideo.UserData.calcSCOS_beforeVideoStop_Flag = false;
% handles.fig_SCOS_GUI.UserData.isVideoRunning = false;
handles.fig_SCOS_GUI.UserData.recFolder = [ fileparts(fileparts(mfilename('fullpath'))) '\Records\timeData' ];
if ~exist(handles.fig_SCOS_GUI.UserData.recFolder,'dir'); mkdir(handles.fig_SCOS_GUI.UserData.recFolder); end
recTimestamp = datestr(datetime('now'),'yyyy-mm-dd_HH-MM-SS');
handles.fig_SCOS_GUI.UserData.recName = fullfile(handles.fig_SCOS_GUI.UserData.recFolder, ['Rec_' recTimestamp '.mat']);
if ~exist(handles.fig_SCOS_GUI.UserData.recFolder,'file')
    mkdir(handles.fig_SCOS_GUI.UserData.recFolder);
end
handles.tgl_startVideo.UserData.saveEachNframes = 200;


handles.fig_SCOS_GUI.UserData.CamData.videoFormat = 'Mono12';
handles.fig_SCOS_GUI.UserData.CamData.triggerSource = 'Line1';
% switch  handles.fig_SCOS_GUI.UserData.CamData.videoFormat
    handles.fig_SCOS_GUI.UserData.CamData.maxGain = 24;
%     case 'Mono8'
%         handles.fig_SCOS_GUI.UserData.CamData.maxGain = 36;
%     case 'Mono12','Mono10
%         handles.fig_SCOS_GUI.UserData.CamData.maxGain = 24;
%     otherwise 
%         error(['Unknown Video format "' handles.fig_SCOS_GUI.UserData.CamData.videoFormat '"']);
% end
handles.fig_SCOS_GUI.UserData.CamData.maxExpT = 10000; % in ms
handles.fig_SCOS_GUI.UserData.CamData.maxTriggerDelay = 1e6; % in us
handles.fig_SCOS_GUI.UserData.versionTag = 'ver9';

% --- Outputs from this function are returned to the command line.
function varargout = SCOS_GUI_OutputFcn(hObject, eventdata, handles) 
% Get default command line output from handles structure
varargout{1} = handles.output;

%% == Calc SCOS Buttons
function btn_start_scos_Callback(hObject, eventdata, handles)
if isequal(hObject.String,'Start SCOS') % 
    if handles.tgl_startVideo.UserData.calcSCOS_Flag
        return; % do nothing - > theoretically not suppose to get here
    end
    handles.tgl_startVideo.UserData.calcSCOS_Flag = true;
    handles.tgl_startVideo.UserData.resetSCOS_clock = tic;

    handles.tgl_startVideo.UserData.calcSCOS_Flag = true;
    handles.tgl_startVideo.UserData.resetSCOS_clock = tic;    
    
    set(hObject,'String','Stop SCOS')
else
    if ~isempty( find(isnan(handles.tgl_startVideo.UserData.scosTime),1) )  && ...
            find(isnan(handles.tgl_startVideo.UserData.scosTime),1) > 1
        handles.tgl_startVideo.UserData.calcSCOS_Flag = false;
        handles.tgl_startVideo.UserData.calcSCOS_lastClock = handles.tgl_startVideo.UserData.scosTime(find(isnan(handles.tgl_startVideo.UserData.scosTime),1)-1)  ; 
    end
    %TBD
    handles.tgl_startVideo.UserData.calcSCOS_Flag = false;
    handles.tgl_startVideo.UserData.calcSCOS_lastClock = handles.tgl_startVideo.UserData.scosTime(find(isnan(handles.tgl_startVideo.UserData.scosTime),1)-1)  ; 

    set(hObject,'String','Start SCOS');
    
    frameRate     = handles.edt_frameRate.Value;
    fr = handles.tgl_startVideo.UserData.src.AcquisitionFrameRate
    Gain          = handles.edt_gain.Value;
    exposureTime  = handles.edt_exposureTime.Value;
    triggerDelay  = handles.edt_triggerDelay.Value;
               
    if ~isempty(handles.tgl_startVideo.UserData.scosTime) && any(~isnan(handles.tgl_startVideo.UserData.scosTime))
        scosData = handles.tgl_startVideo.UserData.scosData;
        scosTime = handles.tgl_startVideo.UserData.scosTime;
        save(handles.fig_SCOS_GUI.UserData.recName,'scosData','scosTime','frameRate','exposureTime','Gain','triggerDelay');
    end 
    
    % handles.tgl_startVideo.UserData.resetSCOS_clock = tic;
end

function btn_reset_scos_Callback(hObject, eventdata, handles)
plot(handles.ax_scos,0,0); % reset axes

handles.tgl_startVideo.UserData.resetSCOS_Flag = true;
handles.tgl_startVideo.UserData.resetSCOS_clock = tic;
handles.tgl_startVideo.UserData.calcSCOS_lastClock = 0;

handles.tgl_startVideo.UserData.resetSCOS_Flag = true;
handles.tgl_startVideo.UserData.resetSCOS_clock = tic;
handles.tgl_startVideo.UserData.calcSCOS_lastClock = 0;
    
function edt_windowSize_Callback(hObject, eventdata, handles)

function edt_windowSize_CreateFcn(hObject, eventdata, handles)
if ispc && isequal(get(hObject,'BackgroundColor'), get(0,'defaultUicontrolBackgroundColor'))
    set(hObject,'BackgroundColor','white');
end

function ax_scos_CreateFcn(hObject, eventdata, handles)

function btn_setSCOSRecName_Callback(hObject, eventdata, handles)
    [file,folder]  = uiputfile([handles.fig_SCOS_GUI.UserData.recFolder '\*.mat']);
    if folder == 0
        return
    end
    handles.fig_SCOS_GUI.UserData.recFolder = folder;
    handles.fig_SCOS_GUI.UserData.recName = fullfile(handles.fig_SCOS_GUI.UserData.recFolder,file);

function btn_open_recording_Callback(hObject, eventdata, handles)
    answer = questdlg('Open last saved recording?','','Open Last','Choose Recording','Open Last');
    if strcmp(answer,'Open Last')
        recFiles = dir([ handles.fig_SCOS_GUI.UserData.recFolder '\*.mat' ]);
        [~,last_rec_ind] = max([recFiles.datenum]);
        fileName = recFiles(last_rec_ind).name;
        
        D = load([handles.fig_SCOS_GUI.UserData.recFolder filesep fileName ]);
    else
        [fileName , filePath] =  uigetfile([ handles.fig_SCOS_GUI.UserData.recFolder '\*.mat' ]);
        if fileName == 0
            return;
        end
        D = load([filePath filesep fileName ]);
    end    

    firstNonNunIdx = find(isnan(D.scosTime),1);
    D.scosData(firstNonNunIdx:end) = [];
    D.scosTime(firstNonNunIdx:end) = [];
    
    if isempty(D.scosData)
        msgbox([ fileName  '  recording is empty']);
        return;
    end
    fig = figure('Name',[ 'Scos Result' fileName ]);
    subplot(2,1,1)
    plot(D.scosTime,1./D.scosData);
    ylabel('1/\kappa^2');
    xlabel('time [min]');
    title(['SCOS Results: ' fileName(1:end-4)],'interpreter','none');

    % validate frame rate:
    if isempty(firstNonNunIdx);  firstNonNunIdx = Inf; end
    timeDiff = median(diff(D.scosTime(1:min(100,firstNonNunIdx))))*60;
    frameRateCalc = round(1/timeDiff,2)
    if isnan(frameRateCalc); errordlg('Could not extract frame rate'); return; end
        
    subplot(2,1,2)
    if isfield(D,'frameRate')
        frameRate  = D.frameRate;
        if abs( frameRateCalc / frameRate ) > 1.2 || abs( frameRateCalc / frameRate ) < 0.8
            warning('frameRateCalc = %g  frameRateCamera = %g',frameRateCalc,frameRate); 
        end
    else        
        frameRate = frameRateCalc;
    end
    [corr_SNR,  corr_FFT , corr_freq, corr_pulseFreq, corr_pulseBPM] = CalcSNR_Pulse(1./D.scosData,frameRate,0);
    plot(corr_freq,corr_FFT)
    ylabel(' FFT')
    title(sprintf('FFT: SNR=%.2g, Pulse=%.0fbpm',corr_SNR,corr_pulseBPM));
    xlim([0 corr_freq(end)]);
    xlabel('Frequency [Hz]')

    
%% == Change CamParams Buttons
function edt_exposureTime_Callback(hObject, eventdata, handles)
expTNum = str2double(hObject.String);
if isnan(expTNum)
    hObject.String = hObject.Value; % set the last value
    errordlg('exposure time should be a number!');
    return;
elseif expTNum < 0 || expTNum > handles.fig_SCOS_GUI.UserData.CamData.maxExpT
    hObject.String = hObject.Value;
    errordlg(['exposure time should be in the range [0.021' num2str(handles.fig_SCOS_GUI.UserData.CamData.maxExpT) ' ms]'])
    return;
end

if ~isfield(handles.tgl_startVideo.UserData,'src') || ~isvalid(handles.tgl_startVideo.UserData.src)
    vid = videoinput("gentl", 1, handles.fig_SCOS_GUI.UserData.CamData.videoFormat);
    src = getselectedsource(vid);
    src.ExposureTime = expTNum * 1e3; % src expects microseconds
    delete(vid);
    clear vid
else
    handles.tgl_startVideo.UserData.src.ExposureTime = expTNum * 1e3; % src expects microseconds
end
hObject.Value = expTNum;

function edt_gain_Callback(hObject, eventdata, handles)

GainNum = str2double(hObject.String);
if isnan(GainNum)
    hObject.String = hObject.Value; % set the last value
    errordlg('Gain should be a number!');
    return;
elseif GainNum < 0 || GainNum > handles.fig_SCOS_GUI.UserData.CamData.maxGain
    hObject.String = hObject.Value;
    errordlg(['Gain should be in the range [0' num2str(handles.fig_SCOS_GUI.UserData.CamData.maxGain) '] dB'])
    return;
end

if ~isfield(handles.tgl_startVideo.UserData,'src') || ~isvalid(handles.tgl_startVideo.UserData.src)
    vid = videoinput("gentl", 1, handles.fig_SCOS_GUI.UserData.CamData.videoFormat);
    src = getselectedsource(vid);
    src.Gain = GainNum;
    delete(vid);
    clear vid
else
    handles.tgl_startVideo.UserData.src.Gain = GainNum;
end
hObject.Value = GainNum;

function edt_triggerDelay_Callback(hObject, eventdata, handles)

triggerDelayNum = str2double(hObject.String);
if isnan(triggerDelayNum)
    hObject.String = hObject.Value;
    errordlg('Trigger Delay should be a number!');
    return;
end

if ~isfield(handles.tgl_startVideo.UserData,'src') || ~isvalid(handles.tgl_startVideo.UserData.src)
    vid = videoinput("gentl", 1, handles.fig_SCOS_GUI.UserData.CamData.videoFormat);
    src = getselectedsource(vid);
    src.TriggerDelay = triggerDelayNum;
    delete(vid);
    clear vid
else
    handles.tgl_startVideo.UserData.src.TriggerDelay = triggerDelayNum; % should be in microseconds
end

hObject.Value = triggerDelayNum;



function chk_externalTrigger_Callback(hObject, eventdata, handles)
    % -- set the external trigger field        
    if ~isfield(handles.tgl_startVideo.UserData, 'src') || ~isvalid(handles.tgl_startVideo.UserData.src)
        vid_was_valid = isfield(handles.tgl_startVideo.UserData,'vid') && isvalid(handles.tgl_startVideo.UserData.vid);
        if ~vid_was_valid
            vid = videoinput("gentl", 1, handles.fig_SCOS_GUI.UserData.CamData.videoFormat);
        else
            vid = handles.tgl_startVideo.UserData.vid;
        end
        src = getselectedsource(vid);

        if hObject.Value
            set( src, 'TriggerMode', 'on');
            src.TriggerMode = 'on';
            set( src, 'AcquisitionFrameRateEnable' , 'False'); % not sure it's really needed
            set( src, 'TriggerSource' ,handles.fig_SCOS_GUI.UserData.CamData.triggerSource)
        else
            set( src, 'TriggerMode', 'off');
            set( src, 'AcquisitionFrameRateEnable' , 'True'); 
            frameRate = get(src,'AcquisitionFrameRate');
        end
        if ~vid_was_valid
            delete(vid);
        end
    else
        if hObject.Value
            set( handles.tgl_startVideo.UserData.src,'TriggerMode' , 'on'); 
            set( handles.tgl_startVideo.UserData.src, 'AcquisitionFrameRateEnable','False');
            set( handles.tgl_startVideo.UserData.src, 'TriggerSource' ,handles.fig_SCOS_GUI.UserData.CamData.triggerSource)
        else
            set( handles.tgl_startVideo.UserData.src ,'TriggerMode' ,'off' );
            set( handles.tgl_startVideo.UserData.src, 'AcquisitionFrameRateEnable','True');  
            frameRate = get( handles.tgl_startVideo.UserData.src,'AcquisitionFrameRate');
        end
    end   
    
    % --- change the FrameRate field accordingly 
    if hObject.Value        
        if isfield(handles.fig_SCOS_GUI.UserData,'last_external_trigger_frequency')
            default_ans = handles.fig_SCOS_GUI.UserData.last_external_trigger_frequency;
        else
            default_ans = '';
        end
        
        answer = inputdlg('What is the frequency of external trigger? [Hz]' , '', [1 45], {default_ans});
        if isnan(str2double(answer{1})); errordlg('frequency must be a number');
            set(hObject,'Value',0)
            return;
        end
        
        if str2double(answer{1})<=0; errordlg('frequency must be a positive number')
            set(hObject,'Value',0)
            return;            
        end
        handles.fig_SCOS_GUI.UserData.last_external_trigger_frequency = answer{1};
        
        set(handles.txt_frameRate,'String','External Trigger Frame Rate [Hz]')
        set(handles.edt_frameRate,'Value',str2double(answer{1}));
        set(handles.edt_frameRate,'String',answer{1})
    else % returned back to be camera inner trigger
        set(handles.txt_frameRate,'String','Frame Rate [Hz]')
        set(handles.edt_frameRate,'Value', frameRate );
        set(handles.edt_frameRate,'String', num2str(frameRate ))        
    end    

function edt_frameRate_Callback(hObject, eventdata, handles)

frameRateNum = str2double(hObject.String);
if isnan(frameRateNum)
    errordlg('Frame Rate must be a number');
    set(handles.edt_frameRate,'String',num2str(hObject.Value));
    return;
end

set(handles.edt_frameRate,'Value',frameRateNum);

if handles.chk_externalTrigger.Value % we are working with external trigger
    handles.fig_SCOS_GUI.UserData.last_external_trigger_frequency = frameRate;
else     % we are working with internal camera frame rate 
    if isfield(handles.tgl_startVideo.UserData,'src') && isvalid(handles.tgl_startVideo.UserData.src)
        handles.tgl_startVideo.UserData.src.AcquisitionFrameRateEnable = 'True';
        handles.tgl_startVideo.UserData.src.AcquisitionFrameRate = frameRateNum;
    else
        vid = videoinput("gentl", 1, handles.fig_SCOS_GUI.UserData.CamData.videoFormat);
        src = getselectedsource(vid);
        src.AcquisitionFrameRateEnable = 'True';
        src.AcquisitionFrameRate = frameRateNum;
        delete(vid);
        %tgl_startVideo_Callback(handles.tgl_startVideo, eventdata, handles);
    end
end

function edt_gain_CreateFcn(hObject, eventdata, handles)
if ispc && isequal(get(hObject,'BackgroundColor'), get(0,'defaultUicontrolBackgroundColor'))
    set(hObject,'BackgroundColor','white');
end
function edt_exposureTime_CreateFcn(hObject, eventdata, handles)
if ispc && isequal(get(hObject,'BackgroundColor'), get(0,'defaultUicontrolBackgroundColor'))
    set(hObject,'BackgroundColor','white');
end
function edt_triggerDelay_CreateFcn(hObject, eventdata, handles)
if ispc && isequal(get(hObject,'BackgroundColor'), get(0,'defaultUicontrolBackgroundColor'))
    set(hObject,'BackgroundColor','white');
end
function edt_frameRate_CreateFcn(hObject, eventdata, handles)
if ispc && isequal(get(hObject,'BackgroundColor'), get(0,'defaultUicontrolBackgroundColor'))
    set(hObject,'BackgroundColor','white');
end

%% == Video Related Buttons
function btn_updateROI_Callback(hObject, eventdata, handles)


answer = questdlg('How do you want to choose ROI','Update ROI','Auto','Manual','Auto');
hData = findobj(handles.ax_image.Children,'Type','image');
im = double(get(hData,'Cdata'));


if strcmp(answer,'Auto')   
    x = 1 : size(im, 2); % Columns.
    y = 1 : size(im, 1); % Rows.
    [X, Y] = meshgrid(x, y);
    meanIm = mean(im(:));
    centerOfMassX = mean(im(:) .* X(:)) / meanIm;
    centerOfMassY = mean(im(:) .* Y(:)) / meanIm;
    % figure; imshowpair(CreateCircleMask(size(im),5,centerOfMassY,centerOfMassX),im)
    
    % Find MaxI
    maxI = mean(im(CreateCircleMask(size(im),5,centerOfMassY,centerOfMassX)));
    
    % Find Expected Radius
    relativeIforCircle = 0.3;
    numOfPixelsInSpot = nnz(im(:) > maxI*relativeIforCircle);
    approxRadius = sqrt(numOfPixelsInSpot/pi());
    
    [centers, radii] = imfindcircles(im > maxI*relativeIforCircle,round(approxRadius*[0.9 1.1]),'ObjectPolarity','bright','Sensitivity',0.99);
    if numel(radii) > 1 
        [circ.Radius,max_ind] = max(radii);
        circ.Center = centers(:,max_ind);
    elseif numel(radii) == 1 
        circ.Radius = radii;
        circ.Center = centers;
    else
        errordlg('Could not detect circle :(')
        return;
    end
    if isfield(handles.fig_SCOS_GUI.UserData,'ROI')
        delete(handles.fig_SCOS_GUI.UserData.ROI.circ_handle);
    end

    mask = false(size(im,1),size(im,2));
    [x,y] = meshgrid(1:size(im,2),1:size(im,1));
    mask((x-circ.Center(1)).^2 + (y-circ.Center(2)).^2 < circ.Radius^2 ) = true;
    
else
    axis(handles.ax_image);
    if isfield(handles.fig_SCOS_GUI.UserData,'ROI')
        delete(handles.fig_SCOS_GUI.UserData.ROI.circ_handle);
    end

    c_tmp = drawcircle('Color','r','FaceAlpha',0.2);
    circ.Center = c_tmp.Center;
    circ.Radius = c_tmp.Radius;
    delete(c_tmp);
    mask = false(size(im,1),size(im,2));
    [x,y] = meshgrid(1:size(im,2),1:size(im,1));
    mask((x-circ.Center(1)).^2 + (y-circ.Center(2)).^2 < circ.Radius^2 ) = true;
end


h = viscircles(handles.ax_image, circ.Center , circ.Radius,'Color','r','EnhanceVisibility',false,'LineWidth',1);
handles.fig_SCOS_GUI.UserData.ROI.mask = mask;
handles.fig_SCOS_GUI.UserData.ROI.circ = circ;
handles.fig_SCOS_GUI.UserData.ROI.circ_handle = h;



btn_AutoClim_Callback(handles.btn_AutoClim, eventdata, handles);

function btn_AutoClim_Callback(hObject, eventdata, handles)
% hObject    handle to btn_AutoClim (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user data (see GUIDATA)
 hData = findobj(handles.ax_image.Children,'Type','image');  
 im = get(hData,'CData');
 
 if isfield(handles.fig_SCOS_GUI.UserData,'ROI')
     mask = handles.fig_SCOS_GUI.UserData.ROI.mask;
 else
     mask = true(size(im));
 end
    
 [N,edges] = histcounts(im(mask),1000,'Normalization','cdf');
 
 upperLim = ceil(edges(find(N > 0.95,1)));
 lowerLim = floor(edges(find(N > 0.05,1)));
 minStretch = 6;
 if upperLim-lowerLim < minStretch
     lowerLim = max(0,mean([upperLim,lowerLim]) - minStretch/2) ;
     upperLim = upperLim + minStretch;
 end
 set(handles.ax_image,'CLim',[ lowerLim upperLim]);
        
function btn_record_Callback(hObject, eventdata, handles)
% hObject    handle to btn_record (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user data (see GUIDATA)
              
% currFolder = fileparts(mfilename('fullpath'));
mfilefolder = fileparts(mfilename('fullpath'));
last_folder_matfile = [mfilefolder '\SCOS_GUI_lastrec.mat'];
if exist(last_folder_matfile,'file')
     tmp = load(last_folder_matfile);
     last_record_folder = tmp.recFolder;
     if ~exist(last_record_folder,'dir')
         last_record_folder = 0;
     end
else
    last_record_folder = 0;
end

if  last_record_folder == 0  
    last_record_folder = [fileparts(fileparts(mfilefolder)) filesep 'Records']; 
end

recFolder = uigetdir(fileparts(last_record_folder),'Please Select Folder in which to save recording');
if recFolder==0
    return;
end
save(last_folder_matfile,'recFolder');

set(handles.tgl_startVideo,'Enable','Off');
% stop running video and delete all opened vid
wasVideoRunning = handles.tgl_startVideo.Value;

if wasVideoRunning
    % stop video
    tgl_startVideo_Callback(handles.tgl_startVideo, eventdata, handles)
    pause(0.05);
    kk=0;
    while ( (isfield(handles.tgl_startVideo.UserData,'src') && isvalid(handles.tgl_startVideo.UserData.src)) || ( isfield(handles.tgl_startVideo.UserData,'vid') && isvalid(handles.tgl_startVideo.UserData.vid) ) ) && kk<20
        pause(0.02);
        disp('pausing 0.02 sec')
        kk=kk+1;
    end
    
    if (isfield(handles.tgl_startVideo.UserData,'src') && isvalid(handles.tgl_startVideo.UserData.src)) || ( isfield(handles.tgl_startVideo.UserData,'vid') && isvalid(handles.tgl_startVideo.UserData.vid) )
        warning('for some reason video was not stopped')
        if isfield(handles.tgl_startVideo.UserData,'vid') && isvalid(handles.tgl_startVideo.UserData.vid)
            delete(handles.tgl_startVideo.UserData.vid);
        end
        objects = imaqfind;
        if numel(objects)>0;  delete(objects(1)); end
    end
end


if handles.chk_externalTrigger.Value
    %answer = inputdlg('What is the pulse generator frequency?','Pulse Generato frequence',[1 35]);
    frameRate = str2double(handles.edt_frameRate.String);
    if isnan(frameRate)
        errordlg('Wrong Frame Rate');
        return;
    end
else
    vid = videoinput("gentl", 1, handles.fig_SCOS_GUI.UserData.CamData.videoFormat);
    src = getselectedsource(vid);
    frameRate = round(get(src,'AcquisitionFrameRate'),5);
    delete(vid);
end

nOfFrames = round(str2double(handles.edt_nOfSeconds.String)*frameRate);
camParams.Gain = str2double(handles.edt_gain.String);
camParams.ExposureTime= str2double(handles.edt_exposureTime.String)*1000;

if handles.chk_externalTrigger.Value %triggerconfig(vid, 'hardware')
    camParams.TriggerMode = 'on';
else
    camParams.TriggerMode = 'off';
end

windowSize = str2double(handles.edt_windowSize.String); 

% beepintervalSeconds = 120;
% beebIntervalFrames  = beepintervalSeconds*frameRate;

[~,recName]= RecordFromCamera(nOfFrames, camParams, [], recFolder ,'.tiff','',['FR' num2str(frameRate) 'Hz'],0,0,[]); 
if isfield(handles.fig_SCOS_GUI.UserData,'ROI')
    SCOSvsTimeUpdated(recName ,windowSize, 1, handles.fig_SCOS_GUI.UserData.ROI);
else
    SCOSvsTimeUpdated(recName ,windowSize, 1);
end

set(handles.tgl_startVideo,'Enable','On');

if wasVideoRunning
    set(handles.tgl_startVideo,'String','Start Video');
    tgl_startVideo_Callback(handles.tgl_startVideo, eventdata, handles)
end

function edt_nOfSeconds_Callback(hObject, eventdata, handles)

function edt_nOfSeconds_CreateFcn(hObject, eventdata, handles)
if ispc && isequal(get(hObject,'BackgroundColor'), get(0,'defaultUicontrolBackgroundColor'))
    set(hObject,'BackgroundColor','white');
end

function ax_image_CreateFcn(hObject, eventdata, handles)        

%% ================  Run Video ======================================================
function tgl_startVideo_Callback(hObject, eventdata, handles)

if hObject.Value == 0
    % stop calculating and plotting scos
    handles.tgl_startVideo.UserData.calcSCOS_beforeVideoStop_Flag = handles.tgl_startVideo.UserData.calcSCOS_Flag;
    if handles.tgl_startVideo.UserData.calcSCOS_Flag  
        btn_start_scos_Callback(handles.btn_start_scos, eventdata, handles); % stop scos
    end
    
    % stop vid
    if isfield(hObject.UserData,'vid') && isvalid(hObject.UserData.vid)
        vid = hObject.UserData.vid;
        stop(vid)
%         delete(vid);
    else
        vidobj = imaqfind;
        if numel(vidobj)>0;  stop(vidobj(1)); delete(vidobj(1)); end
    end
    
    % set(hObject,'String','Start Video') - > this will happen after video is stopped in other instance of the same function
else %  get(hObject,'String') == 'Start Video' 
    set(hObject,'String','Starting...');

    if ~isfield(hObject.UserData,'vid') || ~isvalid(hObject.UserData.vid)         
        try
            if isfield(hObject.UserData,'vid') 
                delete(hObject.UserData.vid);
            end

            % delete any other opened vidobjects
            vidobj = imaqfind;
            if ~isempty(vidobj); delete(vidobj(1)); end

            vid = videoinput("gentl", 1, handles.fig_SCOS_GUI.UserData.CamData.videoFormat);
            vid.FramesPerTrigger = Inf; 
            hObject.UserData.vid = vid;
        catch err
            if isequal(err.identifier,'imaq:videoinput:noDevices')
                errordlg('Connect camera then try again');
                return
            else
                errordlg({'Error While Starting videoinput ',err.message});
                return;
            end
        end
    else
        vid = hObject.UserData.vid;
    end
    
    if ~isfield(hObject.UserData,'src') || ~isvalid(hObject.UserData.src)
        src = getselectedsource(vid);    
        hObject.UserData.src = src;
        
        if strcmpi(src.TriggerMode,'On') %handles.chk_externalTrigger.Value
            triggerconfig(vid, 'hardware');
        end
        
        % init camera params
        handles.edt_exposureTime.String = src.ExposureTime * 1e-3;
        handles.edt_exposureTime.Value  = src.ExposureTime * 1e-3;
        handles.edt_gain.String = src.Gain;
        handles.edt_gain.Value  = src.Gain;
        handles.edt_triggerDelay.String = src.TriggerDelay;
        handles.edt_triggerDelay.Value  = src.TriggerDelay;
        handles.edt_frameRate.String = src.AcquisitionFrameRate;
        handles.edt_frameRate.Value  = src.AcquisitionFrameRate;
        handles.chk_externalTrigger.Value = strcmpi(src.TriggerMode,'on');
                
        if handles.chk_externalTrigger.Value
            chk_externalTrigger_Callback(handles.chk_externalTrigger, eventdata, handles);
        end
    else
        src = hObject.UserData.src;
    end
    set(src,'TriggerSource',handles.fig_SCOS_GUI.UserData.CamData.triggerSource)
    detectorName = 'Basler_1440GS_Vika01'; 
    dData = load([fileparts(fileparts(mfilename('fullpath'))) '\camerasData\' detectorName '\readNoiseVsGain.mat']);  % detector Data
   
    k = 1;    
    if ~isrunning(vid); start(vid); end

    pauseTriggerMode = 0.05;
    pauseUsualMode = 0.01;
    maxFramesPerRead = 5;

    if strcmpi(src.TriggerMode,'On')
        pauseInterval = pauseTriggerMode;
    else
        pauseInterval = pauseUsualMode;
    end
    pause(pauseInterval);
    
    scos_ind = find(isnan(hObject.UserData.scosTime),1);
    if isempty(scos_ind); scos_ind = numel(hObject.UserData.scosTime) + 1; end
    currXlim = get(handles.ax_scos,'XLim');
    
    if hObject.UserData.calcSCOS_beforeVideoStop_Flag
        btn_start_scos_Callback(handles.btn_start_scos, eventdata, handles)
    end
    numOfMissedFrames = 0;
    
    set(hObject,'String','Stop Video');

    pause(src.ExposureTime*1e-6*1.05); % o.w. it does not have vid.FramesAvailable
    while isvalid(handles.fig_SCOS_GUI) && hObject.Value && isvalid(hObject.UserData.src) && isvalid(vid)
        % ~handles.fig_SCOS_GUI.UserData.stopVideoFlag
        drawnow limitrate;
        if ~hObject.Value
            break;
        end
        if ~vid.FramesAvailable
            pause(0.001);
            continue;
        end

        % --- Get a small batch of frames ------------------------
        nFramesToRead = min(vid.FramesAvailable, maxFramesPerRead);
        currImagesBuff = getdata(vid, nFramesToRead);
        drawnow limitrate;
        if hObject.UserData.calcSCOS_Flag
            tm = toc(hObject.UserData.resetSCOS_clock) ;
        end
%         fprintf('%d \t',size(currImagesBuff,3)-1);
%         if mod(k,30)==0; fprintf('\n'); end
        im = squeeze( currImagesBuff(:,:,end,end) );
        numOfMissedFrames = numOfMissedFrames + size(currImagesBuff,3)-1;
        % --- Show in Axis -------------------------
        if isfield(handles.fig_SCOS_GUI.UserData,'ROI')
            mask = handles.fig_SCOS_GUI.UserData.ROI.mask;
        else
            mask = true(size(im)); %CreateCircleMask(size(im));
        end
        
        if k==1
            [~,hImage] = my_imagesc(im,mask,handles.ax_image);
                        
            if isfield(handles.fig_SCOS_GUI.UserData,'ROI')
                circ = handles.fig_SCOS_GUI.UserData.ROI.circ;
                viscircles(handles.ax_image, circ.Center , circ.Radius,'Color','r','EnhanceVisibility',false,'LineWidth',1);
            end
        else
            set(hImage, 'CData', im);
        end
        k = k + 1;

        meanI = round(mean(im(mask)));
        pcntl = prctile(im(mask),[5 95]);
        set(handles.txt_avgI,'String',[ '<I>=' num2str(meanI) 'DU;   5%I  =' num2str(pcntl(1)) 'DU;   95%I =' num2str(pcntl(2)) 'DU  '   ]);        

        % --- Calc Scos ---------------------------
        if hObject.UserData.calcSCOS_Flag
           if hObject.UserData.resetSCOS_Flag
               hObject.UserData.scosData = nan(1,10000);
               hObject.UserData.scosTime = nan(1,10000);
               hObject.UserData.resetSCOS_Flag = false;               
               scos_ind=1;
%                timeJump = 0.5 ; %  min
               currXlim = [0 0.5]; 
           end
           if scos_ind > length(hObject.UserData.scosData)
               hObject.UserData.scosData = [ hObject.UserData.scosData nan(1,10000)] ;
               hObject.UserData.scosTime = [ hObject.UserData.scosTime nan(1,10000)] ;
           end

           im = double(im);
           windowSize = str2double(handles.edt_windowSize.String);
           gain_dB = hObject.UserData.src.Gain;
           readoutN   = interp1(dData.gainArr,dData.totNoise, gain_dB ,'spline');
           actualGain = ConvertGain(gain_dB,8,10.5e3);      

           stdIm = stdfilt(im,true(windowSize));
           meanIm = imfilter(im, true(windowSize)/windowSize^2,'conv','same');
           meanImSquare = meanIm.^2;
           Kraw = (stdIm.^2)./meanImSquare ;
           
%            if mod(scos_ind,500) == 0
%                disp(['Shot Noise^2 = ', num2str(actualGain*mean(meanIm(mask))) ])               
%                disp(['Noise^2 = ' num2str(readoutN^2) ])               
%                disp(['Var_raw = ' num2str(mean((stdIm(mask).^2))) ]);               
%            end
           if mod(scos_ind, hObject.UserData.saveEachNframes ) == 0 
               disp(['Saving backup in : ' handles.fig_SCOS_GUI.UserData.recName]);
               scosData = hObject.UserData.scosData;
               scosTime = hObject.UserData.scosTime;
               frameRate = handles.edt_frameRate.Value;
               Gain  = handles.edt_gain.Value;
               exposureTime  = handles.edt_exposureTime.Value;
               triggerDelay  = handles.edt_triggerDelay.Value;
               recFolder = fileparts(handles.fig_SCOS_GUI.UserData.recName);
               if ~exist(recFolder,'dir'); mkdir(recFolder); end
               save(handles.fig_SCOS_GUI.UserData.recName,'scosData','scosTime','frameRate','exposureTime','Gain','triggerDelay');
           end

           hObject.UserData.scosData(scos_ind) = mean(Kraw(mask) - actualGain./meanIm(mask) - ( readoutN^2 + 1/12)./meanImSquare(mask) );   % Kappa_corrected 
           %hObject.UserData.scosData(scos_ind) =  mean( (stdIm(mask)- actualGain*meanIm(mask) - readoutN -1/12)./meanIm(mask) )^2  ;

           hObject.UserData.scosTime(scos_ind) =  tm/60 + hObject.UserData.calcSCOS_lastClock  ; % /60 in order to convert to [min] from [sec]

           plot(handles.ax_scos,hObject.UserData.scosTime(1:scos_ind),1./hObject.UserData.scosData(1:scos_ind),'-');
           % set x and y axis labels
           ylabel(handles.ax_scos,'1/\kappa^2');
           xlabel(handles.ax_scos,'time [min]');
           set(handles.ax_scos,'XLim',currXlim  )
           
           % change XLim if it's not enough            
%            curr_xlim = get(handles.ax_scos,'XLim');
           if currXlim(2) <= hObject.UserData.scosTime(scos_ind)
                currXlim(2) = 2*currXlim(2);
%                 timeJump = 2*curr_xlim(2);
%                 set(handles.ax_scos,'XLim',[0 timeJump*( mod(hObject.UserData.scosTime(scos_ind),timeJump) + 1) ]); 
%                 set(handles.ax_scos,'XLim',[curr_xlim(1) (2*curr_xlim(2)) ] )
           end

           scos_ind = scos_ind + 1;
        end       

         %start(vid);
         pause(pauseInterval);

         % if still there is not frames -> while loop untill there are frames available
         temp_counter = 0;
         while  isvalid(handles.fig_SCOS_GUI) &&  hObject.Value && isvalid(vid) && temp_counter < Inf 
             if  ~isrunning(vid) || vid.FramesAvailable 
                 break;
             else
                 pause(pauseInterval/2); 
                 temp_counter = temp_counter + 1;
             end
         end
    %     trigger(vid);
    end

    if isvalid(hObject);  hObject.Value=0; end
    if isvalid(vid) 
        stop(vid)
%         delete(vid);
    end

    fprintf('Num of missed frames = %d\n',numOfMissedFrames)
    if isvalid(hObject); set(hObject,'String','Start Video'); end
end
     
%% === Close fig_SCOS_GUI ====
function fig_SCOS_GUI_CloseRequestFcn(hObject, eventdata, handles)
if ~isempty(handles)
    if isfield(handles.tgl_startVideo.UserData,'vid') && isvalid(handles.tgl_startVideo.UserData.vid)    
        vid = handles.tgl_startVideo.UserData.vid;
        if isrunning(vid)
            stop(vid);
        end
        handles.tgl_startVideo.UserData.calcSCOS_Flag = false;
        handles.tgl_startVideo.Value = 0;
        pause(0.065); % let it stop from the btn_startVideo_Callback
        if isvalid(vid)
            delete(vid);
        end
        if isfield(handles.tgl_startVideo.UserData,'vid')
            handles.tgl_startVideo.UserData = rmfield(handles.tgl_startVideo.UserData,'vid');
        end
        if isfield(handles.tgl_startVideo.UserData,'src')
            handles.tgl_startVideo.UserData = rmfield(handles.tgl_startVideo.UserData,'src');
        end
    end

    %% Delete vid if there is one opened
    objects = imaqfind;
    if numel(objects)>0;  delete(objects); end

    %% Save
    scosData = handles.tgl_startVideo.UserData.scosData;
    scosTime = handles.tgl_startVideo.UserData.scosTime;
    save(hObject.UserData.recName,'scosData','scosTime');
end
%% Close Fig
pause(0.1)
delete(hObject); %closes the figure
