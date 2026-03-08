function actualGain = GetActualGain(info)

%% Check User Input
if ~isfield(info,'cameraSN') && isfield(info.name,'CameraSN')
    info.cameraSN = num2str(info.name.CameraSN);
end

if ~isfield(info,'cameraSN')
    error('No cameraSN data in info file');
end

%% check if there is a measured value for this camera
switch info.cameraSN
    case '40335410' % Menahem Camera
        if info.nBits == 12
            switch info.name.Gain
                case 16
                    actualGain = 2.3427;
                case 20
                    actualGain = 3.7251;
                case 24
                    actualGain = 5.8617;
                otherwise
                    GainAt24dB = 5.8617;
                    actualGain = GainAt24dB / 10^(24/20) * 10^(info.name.Gain/20);
            end
        elseif info.nBits == 8

            GainAt16dB = 0.146;
            actualGain = GainAt16dB / 10^(16/20) * 10^(info.name.Gain/20);
        else
            error([' Camera SN' info.cameraSN ' Is 12 or 8 Bits Only']);
        end
    case '24828238' % Tomoya Device1
        if info.nBits == 12
            if info.name.Gain == 8
                GainAt16dB = 0.914227869406958;  
                actualGain = GainAt16dB * 10^((info.name.Gain-8)/20);
            elseif info.name.Gain == 16
                GainAt16dB = 2.310091349580211;  % put your value here 2.3101
                actualGain = GainAt16dB * 10^((info.name.Gain-16)/20);
            elseif info.name.Gain == 24
                GainAt24dB = 5.806579358327972;  % put your value here
                actualGain = GainAt24dB * 10^((info.name.Gain-24)/20);
            end
        elseif info.nBits == 8
            if info.name.Gain == 20
                GainAt20dB = 0.230528769675060;  % put your value here
                actualGain = GainAt20dB * 10^((info.name.Gain-36)/20);
            elseif info.name.Gain == 36
                GainAt36dB = 1.468687685052209;  % put your value here
                actualGain = GainAt36dB * 10^((info.name.Gain-36)/20);
            end
        end

    case '25268932' % Tomoya Device2
        if info.nBits == 12
            if info.name.Gain == 8
                GainAt16dB = 0.919622547325621; 
                actualGain = GainAt16dB * 10^((info.name.Gain-8)/20);
            elseif info.name.Gain == 16
                GainAt16dB = 2.292981165322791;  
                actualGain = GainAt16dB * 10^((info.name.Gain-16)/20);
            end
        end
    case '25268933' % Tomoya Device3
        if info.nBits == 12
            if info.name.Gain == 8
                GainAt16dB = 0.913958659880829; 
                actualGain = GainAt16dB * 10^((info.name.Gain-8)/20);
            elseif info.name.Gain == 16
                GainAt16dB = 2.291581725766085; 
                actualGain = GainAt16dB * 10^((info.name.Gain-16)/20);
            end
        end
        
    case '25268934' % Tomoya Device4
        if info.nBits == 12
            if info.name.Gain == 8
                GainAt16dB = 0.909228222449580;  
                actualGain = GainAt16dB * 10^((info.name.Gain-8)/20);
            elseif info.name.Gain == 16
                GainAt16dB = 2.254590311763096;  
                actualGain = GainAt16dB * 10^((info.name.Gain-16)/20);
            end
        end

    case '40335401' % Vika Camera
        if info.nBits == 8
            GainAt0dB = 0.0238;
            actualGain = GainAt0dB * 10^(info.name.Gain/20);
        end
    case '40513592' % Nadav06 a2A1920-160umPRO Camera
        if info.nBits == 10
            GainAt16dB = 0.5846;
            actualGain = GainAt16dB * 10^((info.name.Gain-16)/20);
        end
end


if ~exist('actualGain','var') || isempty(actualGain) || isnan(actualGain)
    if ~isfield(info,'cameraModel')
        error('no ''cameraModel'' field in info input struct ');
    end

    switch info.cameraModel
        case'InGaAsNIT'
            maxCapacity = 17e3;% [e]
            info.name.Gain = 0;
            info.nBits = 14;
        case 'acA1440-220um'  %  Basler
            maxCapacity = 10.5e3;% [e]
        case {'a2A1920-160umPRO','a2A1920-160umBAS'} % Basler
            maxCapacity = 10.4e3; %[e]
        case 'acA3088-57um'
            maxCapacity = 14.4e3;
        otherwise
            error('Unknown Camera Model')
    end
    actualGain = ConvertGain(info.name.Gain,info.nBits,maxCapacity);
    warning('Using Calculated Gain');
end