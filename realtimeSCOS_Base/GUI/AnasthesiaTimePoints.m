function varargout = AnasthesiaTimePoints(varargin)
% ANASTHESIATIMEPOINTS MATLAB code for AnasthesiaTimePoints.fig
%      ANASTHESIATIMEPOINTS, by itself, creates a new ANASTHESIATIMEPOINTS or raises the existing
%      singleton*.
%
%      H = ANASTHESIATIMEPOINTS returns the handle to a new ANASTHESIATIMEPOINTS or the handle to
%      the existing singleton*.
%
%      ANASTHESIATIMEPOINTS('CALLBACK',hObject,eventData,handles,...) calls the local
%      function named CALLBACK in ANASTHESIATIMEPOINTS.M with the given input arguments.
%
%      ANASTHESIATIMEPOINTS('Property','Value',...) creates a new ANASTHESIATIMEPOINTS or raises the
%      existing singleton*.  Starting from the left, property value pairs are
%      applied to the GUI before AnasthesiaTimePoints_OpeningFcn gets called.  An
%      unrecognized property name or invalid value makes property application
%      stop.  All inputs are passed to AnasthesiaTimePoints_OpeningFcn via varargin.
%
%      *See GUI Options on GUIDE's Tools menu.  Choose "GUI allows only one
%      instance to run (singleton)".
%
% See also: GUIDE, GUIDATA, GUIHANDLES

% Edit the above text to modify the response to help AnasthesiaTimePoints

% Last Modified by GUIDE v2.5 10-Jun-2024 07:02:00

% Begin initialization code - DO NOT EDIT
gui_Singleton = 1;
gui_State = struct('gui_Name',       mfilename, ...
                   'gui_Singleton',  gui_Singleton, ...
                   'gui_OpeningFcn', @AnasthesiaTimePoints_OpeningFcn, ...
                   'gui_OutputFcn',  @AnasthesiaTimePoints_OutputFcn, ...
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


% --- Executes just before AnasthesiaTimePoints is made visible.
function AnasthesiaTimePoints_OpeningFcn(hObject, eventdata, handles, varargin)
% This function has no output args, see OutputFcn.
% hObject    handle to figure
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user data (see GUIDATA)
% varargin   command line arguments to AnasthesiaTimePoints (see VARARGIN)

% Choose default command line output for AnasthesiaTimePoints
handles.output = hObject;

% Update handles structure
guidata(hObject, handles);

% UIWAIT makes AnasthesiaTimePoints wait for user response (see UIRESUME)
% uiwait(handles.figure1);
if numel(varargin) < 1
    [file, path] = uiputfile('*.mat','Please Give a Scenario Name');
    if file==0
        closereq(); 
    else
        handles.txt.UserData.fileName = fullfile(path,file);
    end
else
    recName = varargin{2};
    if exist(recName,'file') ~= 7
        closereq();
        error([ recName ' Does not exist!']);
    else
        handles.txt.UserData.fileName = fullfile(recName,'\TimePoints.mat');
    end
end
tmp  = strsplit(handles.txt.UserData.fileName,'\');
shortName = strjoin(tmp(end-2:end-1),'\');
set(handles.figure1,'name',shortName);

% --- Outputs from this function are returned to the command line.
function varargout = AnasthesiaTimePoints_OutputFcn(hObject, eventdata, handles) 
% varargout  cell array for returning output args (see VARARGOUT);
% hObject    handle to figure
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user data (see GUIDATA)

% Get default command line output from handles structure
% varargout{1} = handles.output;


% --- Executes during object creation, after setting all properties.
function txt_CreateFcn(hObject, eventdata, handles)
hObject.String = {};

% --- Executes on button press in btn_Start.
function btn_Start_Callback(hObject, eventdata, handles)

handles.txt.UserData.startTime = tic; 
handles.txt.UserData.T0.datetime = datetime;
handles.txt.UserData.T0.secFromStart = 0;
hObject.Enable = 'off';
handles.txt.String = [ handles.txt.String ; ['T0 - Start                                 ', getTimeStr(handles.txt.UserData.T0.datetime)] ];

% --- Executes on button press in btn_T1.
function btn_T1_Callback(hObject, eventdata, handles)
handles.txt.UserData.T1.datetime = datetime;
handles.txt.UserData.T1.secFromStart = toc(handles.txt.UserData.startTime);
hObject.Enable = 'off';
handles.txt.String = [ handles.txt.String ; ['T1 - Anestethia Induction              ', getTimeStr(handles.txt.UserData.T1.datetime)] ];

% --- Executes on button press in btn_T2.
function btn_T2_Callback(hObject, eventdata, handles)
handles.txt.UserData.T2.datetime = datetime;
handles.txt.UserData.T2.secFromStart = toc(handles.txt.UserData.startTime);
hObject.Enable = 'off';
handles.txt.String = [ handles.txt.String ; ['pre T2 - Pneumoperitoneum          ', getTimeStr(handles.txt.UserData.T2.datetime)] ];

% --- Executes on button press in btn_T3.
function btn_T3_Callback(hObject, eventdata, handles)
handles.txt.UserData.T3.datetime = datetime;
handles.txt.UserData.T3.secFromStart = toc(handles.txt.UserData.startTime);
hObject.Enable = 'Off';
handles.txt.String = [ handles.txt.String ; ['pre T3 - Head Positioning              ', getTimeStr(handles.txt.UserData.T3.datetime)] ];

% --- Executes on button press in btn_other.
function btn_other_Callback(hObject, eventdata, handles)
if isempty(handles.edt_other.String)
    errordlg('Must give a name to the event');
    return;
end
hObject.Value = hObject.Value + 1;
k = hObject.Value;
handles.txt.UserData.Other(k).datetime = datetime;
handles.txt.UserData.Other(k).secFromStart = toc(handles.txt.UserData.startTime);
handles.txt.UserData.Other(k).name = handles.edt_other.String;
handles.txt.String = [ handles.txt.String ; [handles.edt_other.String            '  ', getTimeStr(handles.txt.UserData.Other(k).datetime)] ];

if isequal(handles.btn_T5.Enable,'off')    
    SaveToFiles(handles)
end

% --- Executes on button press in btn_T5.
function btn_T5_Callback(hObject, eventdata, handles)
handles.txt.UserData.T5.datetime = datetime;
handles.txt.UserData.T3.secFromStart = toc(handles.txt.UserData.startTime);
hObject.Enable = 'off';
handles.txt.String = [ handles.txt.String ; ['T5 - Surgery End, Neutral Position  ', getTimeStr(handles.txt.UserData.T5.datetime)] ];
SaveToFiles(handles)

function SaveToFiles(handles)
    D = handles.txt.UserData;
    save(handles.txt.UserData.fileName,'-struct', 'D');
    fid  = fopen([handles.txt.UserData.fileName(1:end-4) '.txt'],'w');
    maxLen = 0;
    for k=1:numel(handles.txt.String)
        tmp = strsplit(handles.txt.String{k}); % last is the time        
        maxLen = max(length(strjoin(tmp(1:end-1))), maxLen);
    end
    
    for k=1:numel(handles.txt.String)
        tmp = strsplit(handles.txt.String{k});
        fprintf(fid,'%s%s%s\r\n',strjoin(tmp(1:end-1)),blanks(maxLen + 3 - length(strjoin(tmp(1:end-1)))),tmp{end});
    end
    fclose(fid);

function ret = getTimeStr(datetimeVar)
    dateTimeCell = strsplit(char(datetimeVar));
    ret = dateTimeCell{2};


function edt_other_Callback(hObject, eventdata, handles)


% --- Executes during object creation, after setting all properties.
function edt_other_CreateFcn(hObject, eventdata, handles)
% hObject    handle to edt_other (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    empty - handles not created until after all CreateFcns called

% Hint: edit controls usually have a white background on Windows.
%       See ISPC and COMPUTER.
if ispc && isequal(get(hObject,'BackgroundColor'), get(0,'defaultUicontrolBackgroundColor'))
    set(hObject,'BackgroundColor','white');
end


% --- Executes during object deletion, before destroying properties.
function figure1_DeleteFcn(hObject, eventdata, handles)
    if isequal(handles.btn_T5.Enable,'off')  && exist([handles.txt.UserData.fileName(1:end-4) '.txt'],'file') % the figure is closed at the end of the run
        winopen([handles.txt.UserData.fileName(1:end-4) '.txt']);
    end
