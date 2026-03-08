function info = GetRecordInfo(recordName)
%% TBD Vika Add Header

    if ~exist(recordName,'file')
        error('Record "%s" does not exist',recordName);
    end
    
    if exist(recordName,'file') == 7 % it's a folder
        infoFilename = fullfile(recordName,'info.mat');
    else % its a file        
        infoFilename = [recordName(1:find(recordName=='.',1,'last')-1),'_info.mat'];
    end
    if exist(infoFilename,'file')
        info = load(infoFilename);
    end
    info.name = GetParamsFromFileName(recordName);
    
    %% Read records info
        %% Read Record
    if exist(recordName,'file') == 7 % it's a folder
        folderpath = recordName;
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
            info.fileType = '.avi';
            vH = VideoReader(fullfile(folderpath,avi_files(1).name) ); 
            info.nBits = vH.BitsPerPixel; 
            info.imageSize = [vH.Hight vH.Width];
        elseif ~isempty(tiff_files)
            tH = Tiff(fullfile(folderpath,tiff_files(1).name),'r');
            info.fileType = '.tiff';
            info.nBits = getTag(tH,'BitsPerSample');
            if info.nBits == 16
                im1 = read(tH);
                if all(mod(im1(1:200),64) == 0)
                    info.nBits = 10;
                elseif all(mod(im1(1:200),16) == 0)
                    info.nBits = 12;
                end
            end

            if ~isfield(info,'cameraSN') % if not recorded from matlab - get camera number from the .tiff file names            
                name_words = strsplit(tiff_files(1).name,'__');
                if numel(name_words) > 1 && ~isnan(str2double(name_words{2}))
                    info.cameraSN = name_words{2};
                    name_words2 = strsplit(name_words{1},'_');
                    info.cameraModel = name_words2{2};
                    info.cameraVendor = name_words2{1};                
                end
            end
            info.imageSize = [getTag(tH,'ImageLength') getTag(tH,'ImageWidth')];
            close(tH)
        end
    else % it's a file    
        [~, ~ , ext] = fileparts(recordName);
        if strcmp(ext,'.avi')
            vH = VideoReader(recordName ); 
            info.fileType = '.avi';
            info.nBits = vH.BitsPerPixel;
            info.imageSize = [vH.Hight vH.Width];
        elseif strcmp(ext,'.tiff') || strcmp(ext,'.tif')
            tH = Tiff(recordName,'r');
            info.fileType = '.tiff';
            info.nBits = tH.BitsPerSample;            
            if info.nBits == 16
                im1 = read(tH);
                if all(mod(im1(1:200),64) == 0)
                    info.nBits = 10;
                elseif all(mod(im1(1:200),16) == 0)
                    info.nBits = 12;
                end
            end

            info.imageSize = [tH.ImageLength tH.ImageWidth];
            close(tH);  
        elseif strcmp(ext,'.mat')
            D = load(recordName);
            fields = fieldnames(D)  ;            
            if ~startsWith(fields{1},'Video')
                error('.mat file should contain video field');
            end
            info.fileType = '.mat';
            if isa(D.(fields{1}),'uint8') 
                info.nBits = 8; 
%             elseif isa(D.fields{2},'uint16') 
%                 info.nBits = 16;
            else
                error('Recording is unknown number of bits')
            end
            info.imageSize = size(D.(fields{1}),1:2);
        else
            error(['Unsupported file type ' ext  ' . Supported types are .tif .tiff .avi '])
        end
    end    
    
    if ~isfield(info,'cameraSN') && isfield(info.name,'cameraSN')
        info.cameraSN = info.name.cameraSN;
        if isnumeric(info.cameraSN)
            info.cameraSN = num2str(info.cameraSN);
        end
    end
