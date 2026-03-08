folderOrig = 'D:\Vika\OneDrive - Bar Ilan University\SCOS_Records\ShaareiZedek\B5 03.11.2024 17-43\Main_expT10ms_Gain20dB_BL100DU_FR5Hz';
folderDest = [ folderOrig(1:end) '_reduced' ];
if ~exist(folderDest,'dir'); mkdir(folderDest); end

if exist([folderOrig ,'\ROI.mat'],'file');  copyfile([folderOrig ,'\ROI.mat'] ,folderDest); end
if exist([folderOrig ,'\info.mat'],'file'); copyfile([folderOrig ,'\info.mat'],folderDest); end
if exist([folderOrig ,'\Mask.mat'],'file'); copyfile([folderOrig ,'\Mask.mat'],folderDest); end


tiffFiles = dir([folderOrig ,'\*tiff']); 
nFrames = numel(tiffFiles);
im1 = imread([folderOrig , filesep, tiffFiles(round(nFrames/2)).name]); % take image from the middle
if isa(im1,'uint8'); nBits=8; elseif isa(im1,'uint16'); nBits=16 ; else ; error('Unknown nBits'); end

if nBits == 16
    if all(mod(im1(1:400),64) == 0)
        devide_by = 64; % because Basler camera for some reason uses last 12 bits instead of first
        nBits = 10;
    elseif all(mod(im1(1:400),16) == 0)
        devide_by = 16 ;
        nBits = 12;
    end
else
    devide_by = 1;
end
if ~exist([folderOrig ,'\info.mat'],'file') 
    save([folderDest '\info.mat'] ,'nBits');
end
keep16bit = (max(im1(:))/devide_by) > 200;
if keep16bit
   tagstruct.BitsPerSample = 16;
   warning('Keeping 16bits!!')
else
   tagstruct.BitsPerSample = 8; 
end


if exist([folderOrig ,'\ROI.mat'],'file')
    roi = load([folderOrig ,'\ROI.mat']);
    yMax = diff(roi.yLimits) + 1;
    xMax = diff(roi.xLimits) + 1;
else
    yMax = size(im1,1);
    xMax = size(im1,2);
    if keep16bit
        error('Nothing to change');
    end
end

%% Prepare target struct
    tagstruct.ImageLength = yMax;
    tagstruct.ImageWidth  = xMax;
    tagstruct.PlanarConfiguration = Tiff.PlanarConfiguration.Chunky;
    tagstruct.Software = 'MATLAB';
    tagstruct.Photometric = Tiff.Photometric.MinIsBlack;
    tagstruct.Compression = Tiff.Compression.None; 

%% Convert tiff Files    

a = tic;
[~,sort_ind] = sort([tiffFiles.datenum]);
tiffFiles = tiffFiles(sort_ind);
nDigits = numel(num2str(nFrames));
for i = 1:nFrames
   % read im
   im = imread([folderOrig , filesep, tiffFiles(i).name])/devide_by;
   
   if ~keep16bit && (max(im(:))) > 255
       error('Should of remained 16 bit or reduce BlackLevel');
   end
   
   % cut im  
   cut_im = im(1:yMax,1:xMax);
   if ~keep16bit
       %convert to uint8 - because the signal is very low, it does not exeeds 256DU anyway
       cut_im = uint8(cut_im);
   end
   if i==1
       my_imagesc(cut_im);
   end
   if mod(i,200)==0
       fprintf('%.1f%%\t',i/nFrames*100);
       if mod(i,2000)==0; fprintf('\n'); end
   end
   
   % write frame to tiff
   oldName = tiffFiles(i).name;
   ind = find(oldName=='_',1,'last');
   prefix = oldName(1:ind);
   frameNum = oldName(ind+1:end-5);
   while numel(frameNum)<nDigits; frameNum = ['0' frameNum]; end %#ok<AGROW>
   newName = [ prefix frameNum '.tiff' ]; 
   t = Tiff([folderDest,filesep,newName],'w');
   setTag(t,tagstruct);
   write(t,cut_im);
   close(t);
end
fprintf('\n Time elepsed = %.0f [min] \n', toc(a)/60);
