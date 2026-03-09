%%-------------------------------------------------------
% [rec, info] = ReadRecord(recName, nOfFrames , startFrame)

% Input : 
%   recName - full path of folder with .tiff/.tif files or single .avi file, 
%                    or full path of .avi/.tif/.tiff file.
%                    Assuming gray scale image.
%   
%   nOfFrames  - [optional] read this number of frames. defualt = Inf
%   startFrame - [optional] first frame to read. default = 1
%
% Output : 
%   rec  - 3D matrix with the record, double
%   info - struct with three fields:
%          filename - parameters from filename
%          cam      - struct of the camera input parameters  
%          setup    - setup parameters as passed by the user to RecordFromCamera 
%
%%-------------------------------------------------------
function [rec, info] = ReadRecord( recName, nOfFrames , startFrame)
    
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
        folderpath = recName;
        % find all .tiff or .tif files
        tiff_files = dir([folderpath, '\*.tiff']) ;
        avi_files  = dir([folderpath, '\*.avi']) ;
        if isempty(tiff_files) && isempty(avi_files)
            error(['There are no ''.tiff'' or ''.avi'' files in input folder ''' folderpath '''']);
        elseif ~isempty(tiff_files) && ~isempty(avi_files)
            error([ '''' folderpath ''' contains both ''.tiff'' or ''.avi'' files. It must contain only one the the file types ' ]);        
        elseif ~isempty(avi_files)
            if numel(avi_files) > 1
                error([ '"' folderpath '" must contain only one .avi file but contains ' num2str(numel(avi_files)) ' files.']);
            end
            [ rec , vH ]  = Avi2Matrix( fullfile(folderpath,avi_files.name) ,nOfFrames , startFrame);
            nBits = vH.BitsPerPixel;
            
        elseif ~isempty(tiff_files)
            [ rec , nBits ] = Tiff2Matrix(folderpath,nOfFrames,startFrame);              
        end
    else % it's a file    
        [~, ~ , ext] = fileparts(recName);
        if strcmp(ext,'.avi')
            [ rec , vH ] = Avi2Matrix( recName ,nOfFrames , startFrame);
            nBits = vH.BitsPerPixel;
        elseif strcmp(ext,'.tiff') || strcmp(ext,'.tif')
            t = Tiff(recName,'r');
            nBits = getTag(t,'BitsPerSample');
            rec = read(t);
            close(t);
            rec = rec(:,:,startFrame:startFrame+nOfFrames-1);                 
        elseif strcmp(ext,'.mat')
            D = load(recName);
            fields = fieldnames(D)  ;
            if ~startsWith(fields{1},'Video')
                error('.mat file should contain video field');
            end
            rec = D.(fields{1});
            nBits = 8;
            if nOfFrames==Inf; nOfFrames = size(rec,3); end
            if startFrame+nOfFrames-1 > size(rec,3)
                error('there are not enough frames in file. Required from %d to %d (total %d frames), but record length is %d',startFrame,startFrame+nOfFrames-1,nOfFrames,size(rec,3))
            end
            rec = rec(:,:,startFrame:startFrame+nOfFrames-1);
        elseif strcmp(ext,'.ptw')
            rec = PTWtoTIFF(recName,0);
            nBits = 14; %true for NIT Camera
        else
            error(['Unsupported file type ' ext  ' . Supported types are .tif .tiff .avi .mat '])
        end
    end

    rec = double(rec);
    if nBits == 16
        if all(mod(rec(1:400),64) == 0)
            rec = rec/64; % because Basler camera for some reason uses last 12 bits instead of first
            nBits = 10;
        elseif all(mod(rec(1:400),16) == 0)
            rec = rec/16;
            nBits = 12;
        end
    end
    %% Read Info
    if nargout > 1
        info = GetRecordInfo(recName); 
        if ~exist('nBits','var')
            info.nBits = nBits;
        end
    end
end


