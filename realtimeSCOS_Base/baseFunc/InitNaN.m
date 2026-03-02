function [out1, out2, out3, out4, out5, out6, out7, out8, out9, out10] = InitNaN(arrSize,cellLength)
    nanArr = nan(arrSize); %#ok<NASGU>
    if nargin > 1        
            for i=1:nargout
                eval(sprintf('out%d=cell(1,%d);',i,cellLength));
                for k=1:cellLength
                    eval(sprintf('out%d{%d}=nanArr;',i,k));
                end
            end
    else    
        for i=1:nargout
            eval(sprintf('out%d=nanArr;',i));
        end
    end