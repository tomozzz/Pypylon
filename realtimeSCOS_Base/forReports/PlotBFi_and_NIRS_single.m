%% Load Data
clear
participantID = 'A12';
plotIflag = 1;

recordsFolder = 'D:\Vika\OneDrive - Bar Ilan University\SCOS_Records\ShaareiZedek';
nirsFolder = [recordsFolder '\NIRS Data']; 

NIRSrecordsDir = dir([ nirsFolder '\' participantID ' *.csv']); % important to keep the space after participantID
NIRSfile = fullfile(nirsFolder, NIRSrecordsDir.name)'; 
figuresFolder = fullfile(recordsFolder,'Docs','figs');

SCOSrecordsDir = dir([ recordsFolder '\' participantID ' *']);
SCOSrecordsDir2 = dir([recordsFolder '\' SCOSrecordsDir.name '\Main*']);
if numel(SCOSrecordsDir2) ~=1
    error('could not find SCOS name');
end
SCOSrecordsDir3 = dir([recordsFolder '\' SCOSrecordsDir.name '\' SCOSrecordsDir2.name '\LocalStd*.mat']);
if numel(SCOSrecordsDir2) ~=1
    disp('More than one file found:')
    diep({SCOSrecordsDir3.name}')
    fileNum = str2double(input('which one to choose? '));
else
    fileNum = 1;
end
SCOSfile = fullfile([recordsFolder '\' SCOSrecordsDir.name '\' SCOSrecordsDir2.name '\' SCOSrecordsDir3(fileNum).name]);

rawName = SCOSrecordsDir2.name;
scosFolderName = SCOSrecordsDir.name;
titleStr = [ scosFolderName ]; % ' ' strrep(rawName,'_',' ') ];
frameRate = ExtractParametersFromString(rawName,'FR'); 
   
%% Timing
timingDir = dir([ recordsFolder '\' scosFolderName '\*timing*.txt']);
if ~isempty(timingDir)
    timingFile = fullfile(recordsFolder , scosFolderName ,timingDir(1).name);
    Timing = readtable(timingFile);
    baselineTime = Timing.Time{1};
    if nnz(baselineTime==':') == 1
       baselineTime = [ baselineTime , ':00'] ;
    end

    if exist(timingFile,'file')
        if exist([fileparts(SCOSfile) '\StartTime.mat'],'file')
            st = load([fileparts(SCOSfile) '\StartTime.mat']);
            startTimeScos = timeofday(st.startTime);
            clear st
        else
            startTimeScos = getSCOSstartTime(fileparts(SCOSfile));
        end
    end
    baselineToScosStart = minutes(duration(startTimeScos) - duration(baselineTime));
    endTime = minutes(duration(Timing.Time{end},'InputFormat','hh:mm') - duration(baselineTime));
else
    error(['Could not Find Timing File for ' participantID ]);
    baselineToScosStart = 0;
end


%% Calc rBFi
S = load(SCOSfile);
BFi = 1./S.corrSpeckleContrast{1};
scosTimeVec = S.timeVec / 60 + baselineToScosStart; % convert to min
xLabelStr = 'time [min]';
rBFi = BFi/mean(BFi(1:round(10*frameRate))); % normalize by first 10 seconds

%% NIRS
NIRS = readtable(NIRSfile);
NIRS = renamevars(NIRS,2:5,{'Date','Time','Left','Right'});
if ~isnumeric(NIRS.Left)
    NIRS.Left  = str2double(NIRS.Left);
end
if ~isnumeric(NIRS.Right)
    NIRS.Right = str2double(NIRS.Right);
end

NIRStimeVec = minutes(NIRS.Time -  duration(baselineTime));
colors = {[1 0 0.8],[0.6 0 0.1]}; % red

        
%% Plot
fig8 = figure('Name',['rBFi: '  rawName ],'Units','Normalized','Position',[0.1,0.1,0.72 ,0.55]);
if plotIflag; N = 3; else; N=2; end
subplot(N,1,1);
plot(scosTimeVec,rBFi);
ylim([0 min(10,max(rBFi))])
xlabel(xLabelStr)
ylabel('rBFi');
xlim([-0.2 endTime+4]);
grid on
set(gca,'FontSize',10);
markTiming(timingFile);
title(titleStr,'interpreter','none','FontSize',14)

if plotIflag
    subplot(N,1,2)
    plot(scosTimeVec,S.meanVec{1});
    xlabel(xLabelStr)
    ylabel('<I> [DU]');
    set(gca,'FontSize',10);
    xlim([-0.2 endTime+4]);
    grid on
end

subplot(N,1,N)
h(1) = plot(NIRStimeVec,NIRS.Left,'color',colors{1},'DisplayName','Left'); hold on;
h(2) = plot(NIRStimeVec,NIRS.Right,'color',colors{2},'DisplayName','Right'); hold on;
xlabel(xLabelStr)
ylabel('rSO2 % ');
xlim([-0.2 endTime+4]);
set(gca,'FontSize',10);
grid on
markTiming(timingFile);
legend(h);

%% Save
if plotIflag; addStr='_with_I'; else; addStr='_no_I'; end
savefig(fig8,[figuresFolder '\' participantID '_scos_nirs' addStr '.fig']);
save([fileparts(figuresFolder) '\short_data\'  participantID '_scos.mat'],'rBFi','scosTimeVec','BFi','NIRStimeVec','NIRS');