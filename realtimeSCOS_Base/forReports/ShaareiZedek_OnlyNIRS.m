%% Init
recordsFolder = 'D:\Vika\OneDrive - Bar Ilan University\SCOS_Records\ShaareiZedek';
nirsFolder = [recordsFolder '\NIRS Data']; 
NIRSrecordsDir = [ dir([ nirsFolder '\A*.csv']); dir([ nirsFolder '\B*.csv']) ];
% recordsnames = cellfun(@(x) startsWith(x,{''}),{recordsDir.name});
% NIRSrecordsnames = {NIRSrecordsDir( cellfun(@(x) contains(x,'2025.01.12'),{NIRSrecordsDir.name}) ).name };
NIRSrecordsnames = {recordsDir.name};

NIRSrecords = strcat(nirsFolder, filesep , NIRSrecordsnames)'; 
figureDir = fullfile(nirsFolder,'figs');

SCOSrecordsDir = [ dir([ recordsFolder '\A*']); dir([ recordsFolder '\B*']) ];

recNames = cell(size(NIRSrecords));
timingFiles = cell(size(NIRSrecords));
for k=1:numel(NIRSrecordsnames)
    tmp = strsplit(NIRSrecordsnames{k});
    recNames{k} = tmp{1};    
    idx=find(cellfun(@(x) startsWith(x,[recNames{k} ' ']),{SCOSrecordsDir.name}));
    if isempty(idx)
        error(['Could not find ' recNames{k} ' SCOS matching folder']);
    end
    timing_file_tmp = dir([recordsFolder filesep SCOSrecordsDir(idx).name filesep '*timing*.txt'] );
    if isempty(timing_file_tmp)
        error([ recNames{k} '  : Could not find timing file']);
    end
    timingFiles{k} = fullfile(recordsFolder, SCOSrecordsDir(idx).name, timing_file_tmp.name);
end

%% Create Figures
prefix = '\figs\';
figs = nan(size(numel(NIRSrecords)));
for ri = 1:numel(NIRSrecords)
    %%
    [~,recName ]  = fileparts(NIRSrecords{ri});
    participantID = recName(1:2);
    disp(participantID)
    Timing = readtable(timingFiles{ri});
    startTime = Timing.Time{1};
    
    NIRS = readtable(NIRSrecords{ri});
    NIRS = renamevars(NIRS,2:5,{'Date','Time','Left','Right'});
    if ~isnumeric(NIRS.Left)
        NIRS.Left  = str2double(NIRS.Left);        
    end
    if ~isnumeric(NIRS.Right)
        NIRS.Right = str2double(NIRS.Right);
    end

    figs(ri) = figure('Units','Normalized','Position',[0.05 0.1 0.7 0.5]);
    NIRStimeVec = minutes(NIRS.Time -  duration(startTime,'InputFormat','hh:mm'));
    % colors = {[0 0.4 0],[0.5 0.8 0.2]}; % green
    colors = {[1 0 0.8],[0.6 0 0.1]}; % red
    h(1) = plot(NIRStimeVec,NIRS.Left,'color',colors{1},'DisplayName','Left'); hold on;
    h(2) = plot(NIRStimeVec,NIRS.Right,'color',colors{2},'DisplayName','Right'); hold on;
    markTiming(timingFiles{ri});
    legend(h); % TBD check which is left and which is right
    xlabel('[min]');
    ylabel('rSO2 % ');
    xlims = xlim;
    endTime = minutes(duration(Timing.Time{end},'InputFormat','hh:mm') - duration(Timing.Time{1},'InputFormat','hh:mm'));
    xlim( [ min( NIRStimeVec(find(~isnan(NIRS.Left) & ~isnan(NIRS.Right),1)) , 0 ) , ...
            max( NIRStimeVec(find(~isnan(NIRS.Left) & ~isnan(NIRS.Right),1,'last')) , endTime*1.05 ) ] );
    title(recName,'interpreter','none');
    set(gca,'OuterPosition',[-0.1,0,1.2,1]);
    savefig(figs(ri),[figureDir '\NIRS ' recName '.fig']);
    saveas(figs(ri),[figureDir '\NIRS ' recName '.png']);
end

%% save to PPT
import mlreportgen.ppt.*

% Start PowerPoint
ppt = Presentation([ figureDir '/NIRS Summary.pptx' ]);
open(ppt);

% List of figure files
figureFiles = dir(fullfile(figureDir, '*.png'));

titleSlide = add(ppt,'Title Slide');
replace(titleSlide, 'Title', 'NIRS Results During Surgery');
replace(titleSlide, 'Subtitle', 'Saarei Zedek 2024');

% Loop through each figure file and add it to the presentation
for i = 1:length(figureFiles)
    % Add a new slide
    slide = add(ppt,'Title and Picture');
    % Insert the figure
    imagePath = fullfile(figureDir, figureFiles(i).name);
    replace(slide,'Picture',Picture(imagePath));
    
    participantID = figureFiles(i).name(6:8);
    replace(slide,'Title',participantID);
end

% Close PowerPoint
close(ppt);
rptview(ppt);