function [nOfFrames, imSize] = GetNumOfFrames(recName)
    if exist(recName,'file') == 7 % it's a folder
        recFolder = recName;
        % find all .tiff or .tif files
        tiff_files = [ dir([recFolder, '\*.tiff']) , dir([recFolder, '\*.tif']) ];
        avi_files  = dir([recFolder, '\*.avi']) ;
        if isempty(tiff_files) && isempty(avi_files)
            error(['No .tiff or .avi files in ''' recFolder '''']);
        elseif ~isempty(tiff_files) && ~isempty(avi_files)
            error([ '''' recFolder ''' contains both ''.tiff'' or ''.avi'' files. It must contain only one the the file types ' ]);        
        elseif ~isempty(avi_files)
            if numel(avi_files) > 1
                error([ '''' recFolder ''' must contain only one .avi file but contains ' num2str(numel(avi_files)) ' such files.']);
            end
            v = VideoReader(fullfile(recFolder,avi_files(1).name));
            nOfFrames = round(v.Duration*v.FrameRate)-1 ; % Not using the field 'NumFrames' because it is not consistent with different matlab versions
            imSize = [ v.Width , v.Height ];
        elseif ~isempty(tiff_files)
            tiff_files = [ dir([ recFolder '\*.tiff']) , dir([recFolder '\*.tif']) ];
            nOfFrames = numel(tiff_files);
            if nargout > 1
                t = Tiff(fullfile(recFolder, tiff_files(1).name));
                imSize =  [getTag(t,'ImageWidth') , getTag(t,'ImageLength') ];
                close(t)
            end
        end
    elseif exist(recName,'file') == 2 % it's a file    
        [~, ~ , ext] = fileparts(recName);
        if strcmp(ext,'.avi')
            v = VideoReader(recName);
            nOfFrames = round(v.Duration*v.FrameRate)-1 ; % Not using the field 'NumFrames' because it is not consistent with different matlab versions
            imSize = [v.Width , v.Height ];
        elseif strcmp(ext,'.tiff') || strcmp(ext,'.tif')
            t = Tiff(recName,'r');
            nOfFrames = getTag(t,'SamplesPerPixel'); % TBD Check!
            imSize =  [getTag(t,'ImageWidth') , getTag(t,'ImageLength') ];
            close(t)
        elseif strcmp(ext,'.mat')
            D = load(recName);
            fields = fieldnames(D);
            if ~startsWith(fields{1},'Video')
                error('.mat file should contain video field');
            end
            nOfFrames = size(D.(fields{1}),3);
            imSize = size(D.(fields{1}),1:2);
        else
            error(['Unsupported file type ' ext  ' . Supported types are .tif .tiff .avi '])
        end
    else
        error(['''' recName  ''' record does not exist! '])
    end
end