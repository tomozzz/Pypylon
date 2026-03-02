function WriteAvi(filename,rec,videoFormat,frameRate,info)
    videoFormat = char(videoFormat); % convert to chat in case it was string

    if ismember( ndims(rec), [3,2] ) 
        if (exist('videoFormat','var') && strcmp(videoFormat,'Mono8') ) || isa(rec,'uint8')   
            profile = 'Uncompressed AVI'; %'Grayscale AVI';
            rec = uint8(rec);
        elseif ( exist('videoFormat','var') && ismember(videoFormat,strcat('Mono',num2cellstr(9:16)))) || isa(rec,'uint16')
            profile = 'Archival';
            rec = uint16(rec);
        else
            error(['rec should be uint8 or uint16 type, or videoFormat should be specified'])
        end
        recToWrite = reshape(rec,[size(rec,1) size(rec,2) 1 size(rec,3) ]);
    elseif ndims(rec) == 4 % it's a RGB image
        % Add here check for videoFormat
        profile = 'Uncompressed AVI';
        recToWrite = uint8(rec) ;
    end
    
    v = VideoWriter( filename ,profile);
%     v.VideoFormat 
%     v.VideoBitsPerPixel 
    if strcmp(profile,'Archival')
        v.MJ2BitDepth; 
        v.VideoCompressionMethod 
        v.LosslessCompression 
    end
    if exist('frameRate','var') && ~isempty(frameRate)
        v.FrameRate = frameRate;
    elseif exist('info','var') 
        v.FrameRate = info.cam.AcquisitionFrameRate;
    end
    
    if exist('info','var')  
        v.UserData.info   = info; % TBD Check!
    end
    
    open(v)
    writeVideo(v,recToWrite);
    close(v)