%%-------------------------------------------------------
% [rec, info] = ReadRecordVarAndMean(recName, nOfFrames , startFrame)

% Input : 
%   recName - full path of folder with .tiff/.tif files or single .avi file, 
%                    or full path of .avi/.tif/.tiff file.
%                    Assuming gray scale image.
%   
%   nOfFrames  - [optional] read this number of frames. defualt = Inf
%   startFrame - [optional] first frame to read. default = 1
%
% Output : 
%   recMean  - 2D matrix of record mean (double)
%   recVar   - 2D matrix with pixels variance over time (double)
%   info - struct with three fields:
%          name - parameters from recName
%          cam      - struct of the camera input parameters  
%          setup    - setup parameters as passed by the user to RecordFromCamera 
%
%%-------------------------------------------------------
function [recMean, recVar, info] = ReadRecordVarAndMean( recName, nOfFrames , startFrame)
    
    %% Check input parameters
    if ~exist(recName,'file')
        error(['Record ''' recName ''' do not exist!'])
    end
    if isstring(recName)
        recName = char(recName);
    end
    
    if ~exist('nOfFrames','var') || isempty(nOfFrames)
        nOfFrames = Inf ; % read all record
    end

    if ~exist('startFrame','var') || isempty(startFrame)
        startFrame = 1 ; % read all record
    end
    
    %% Read Record
    if exist(recName,'file') == 7 % it's a folder
        tiff_files = dir([recName filesep '\*.tiff']) ;
        if isempty(tiff_files)
            error(['No tiff files in ''' recName '''']);
        end
        if ~isinf(nOfFrames)
            if numel(tiff_files) - startFrame + 1 < nOfFrames
                error('File "%s" -> There is no enough frames (requested: %d , in file starting from frame %d: %d) ',recName,nOfFrames,startFrame,numel(tiff_files) - startFrame + 1);
            end
        else
            nOfFrames = numel(tiff_files) - startFrame + 1;
        end
                
        % get first image in order to find out the image size
        t = Tiff(fullfile(recName,tiff_files(1).name),'r');
        nBits = getTag(t,'BitsPerSample');
        im = read(t);
        close(t);

        devide_by = 1;
        if nBits == 16
            if all(mod(im(1:400),64) == 0)
                devide_by = 64; % because Basler camera for some reason uses last 12 bits instead of first
                nBits = 10;
            elseif all(mod(im(1:400),16) == 0)
                devide_by = 16 ;
                nBits = 12;  
            end
        end
        recSum = double(im)/devide_by;
        recSSum  = recSum.^2 ;

        % read all images
        for k = 2:nOfFrames
            im = double(imread(fullfile(recName,tiff_files(k+startFrame-1).name))) / devide_by;
            recSum   = recSum + im ;
            recSSum  = recSSum + im.^2 ;
        end
    else 
        error('This function is for .tiff files');
    end

    recMean = recSum/nOfFrames;
    recVar  = recSSum/nOfFrames - recMean.^2;
    %% Save
    save([recName '\meanIm.mat'],'recMean','recVar');
    
    %% Read Info
    if nargout > 1
        info = GetRecordInfo(recName); 
        if ~exist('nBits','var')
            info.nBits = nBits;
        end
    end
end


