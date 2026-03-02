function [all_XData,all_YData,all_titles] = getDataFromFigure(figName)

    fig = openfig(figName);
    all_ax = findobj(fig, 'type', 'axes');
    all_titles = cellfun(@(T) T.String, get(all_ax, 'title'), 'uniform', 0);
    all_lines = arrayfun(@(A) findobj(A, 'type', 'line'), all_ax, 'uniform', 0);
    all_XData = cellfun(@(L) get(L,'XData'), all_lines, 'uniform', 0);
    all_YData = cellfun(@(L) get(L,'YData'), all_lines, 'uniform', 0);
    for axIdx = 1 : numel(all_YData)
        if iscell(all_YData{axIdx})
            mask = cellfun(@(Y) ~isequal(Y, [0 0]), all_YData{axIdx});
            all_XData{axIdx} = all_XData{axIdx}(mask);
            all_YData{axIdx} = all_YData{axIdx}(mask);
        else
            all_XData{axIdx} = all_XData(axIdx);
            all_YData{axIdx} = all_YData(axIdx);
        end
    end
    
    close(fig)
    
end