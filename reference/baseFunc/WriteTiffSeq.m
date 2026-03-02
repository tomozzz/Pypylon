function WriteTiffSeq(folder,rec,videoFormat)
    videoFormat = char(videoFormat); % convert to chat in case it was string
    
    %% Prepare target struct
    tagstruct.ImageLength = size(rec,1);
    tagstruct.ImageWidth  = size(rec,2);

    if strcmp(videoFormat,'Mono8')
        tagstruct.BitsPerSample = 8;
%         tagstruct.SamplesPerPixel = 1;
        rec = uint8(rec);
    elseif ismember(videoFormat,strcat('Mono',num2cellstr(9:16)))
        tagstruct.BitsPerSample = 16;
%         tagstruct.SamplesPerPixel = 1;
        rec = uint16(rec);
    else
        error(['Unsupported video format "' videoFormat '" for writing .tiffs'])
    end
    tagstruct.PlanarConfiguration = Tiff.PlanarConfiguration.Chunky;
    tagstruct.Software = 'MATLAB';
    tagstruct.Photometric = Tiff.Photometric.MinIsBlack;
    tagstruct.Compression = Tiff.Compression.None; 

    %% Write tiff files
    if exist(folder,'file') ~=7 
       mkdir(folder);
    end
    
    for k=1:size(rec,3)
        t = Tiff([folder,sprintf('\\frame%0*d.tiff',3,k)],'w');
        setTag(t,tagstruct);
        write(t,rec(:,:,k));
        close(t);
    end