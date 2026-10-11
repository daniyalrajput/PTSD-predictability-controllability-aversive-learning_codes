%% BAYESIAN MODEL SELECTION: WINNING-MODEL SUMMARY PLOTS
% Author: Daniyal Rajput, University of Melbourne (original analysis).
%
% PURPOSE: Plot precomputed group BMS summaries for two groups and two
% conditions. This script does not fit models or perform Bayesian inference.
% Frequency and exceedance probability winners are selected independently.
%
% REQUIREMENTS: MATLAB R2020b or later. All local helpers are included.
%
% INPUT: Four Excel files. Each file contains one row per candidate model
% and columns for model name, expected model frequency and exceedance
% probability. Column names and worksheet are configurable below. Model rows
% may appear in any order: they are aligned explicitly by model name.
% Default column names: Model, Frequency, ExceedanceProbability.
% Values must be probabilities in [0,1], not percentages. Each metric's
% values must sum to approximately 1 across the candidate model set.
% Model names must match MODEL_NAMES after case/whitespace normalization.
% Update EXCEEDANCE_COLUMN explicitly if plotting protected exceedance
% probabilities, and update its axis label to describe the chosen metric.
%
% OUTPUT: Four figures, each containing two bars (one per group):
% condition 1 frequency / exceedance; condition 2 frequency / exceedance.
% PNG (600 dpi) and vector PDF exports, plus CSV and MAT winner summaries.
% Group color identifies the group; model texture identifies the model:
% horizontal = Surprise; vertical = Belief Uncertainty; diagonal = Volatility.
% No top title. X-axis: Winning model. A clean group legend is labelled with
% the condition. Values tied within TIE_TOLERANCE cause an error to prevent
% silently displaying a single model as the unique winner.
% MATLAB runtime and figure rendering have not been verified here.

clear; clc; close all;

%% USER CONFIGURATION
inputDir = fullfile(pwd,'bms_inputs');
outdir = fullfile(pwd,'bms_outputs');
% Rows: groups A/B. Columns: conditions 1/2.
inputFiles = ["group_a_condition_1.xlsx","group_a_condition_2.xlsx"; ...
              "group_b_condition_1.xlsx","group_b_condition_2.xlsx"];
GROUP_LABELS = ["Group A","Group B"];
CONDITION_LABELS = ["Controllable","Uncontrollable"];
MODEL_NAMES = ["Surprise","Belief Uncertainty","Volatility"];
MODEL_TEXTURES = ["horizontal","vertical","diagonal"];
SHEET = 1;
MODEL_COLUMN = "Model";
FREQUENCY_COLUMN = "Frequency";
EXCEEDANCE_COLUMN = "ExceedanceProbability";
METRIC_LABELS = ["Expected model frequency","Exceedance probability"];
SUM_TOLERANCE = 1e-3; % Allows small rounding errors in exported summaries.
TIE_TOLERANCE = 1e-12;
png_dpi = 600;
% Group A blue, Group B red; darker condition 1, lighter condition 2.
GROUP_COLORS = zeros(2,3,2);
GROUP_COLORS(:,:,1) = [0.18 0.38 0.78;0.78 0.22 0.22];
GROUP_COLORS(:,:,2) = [0.55 0.80 0.98;0.98 0.82 0.82];
style = struct('tickSize',22,'labelSize',22,'legendSize',20, ...
    'barWidth',0.30,'barLineWidth',1.6,'axisLineWidth',1.0, ...
    'outlineColor',[0.25 0.25 0.25],'hatchColor',[0.2 0.2 0.2], ...
    'hatchLineWidth',1.6,'horizontalGap',0.04,'verticalGap',0.04, ...
    'diagonalGap',0.06);
assert(numel(MODEL_NAMES)==numel(MODEL_TEXTURES),'Each model needs a texture.');
assert(numel(unique(lower(strtrim(MODEL_NAMES))))==numel(MODEL_NAMES), ...
    'MODEL_NAMES must be unique.');

%% READ EXPLICIT FILES AND SELECT WINNERS
if ~isfolder(outdir)
    [ok,msg] = mkdir(outdir);
    if ~ok, error('Cannot create output directory: %s',msg); end
end
summary = cell(2,2);
for c = 1:2
    for g = 1:2
        file = fullfile(inputDir,inputFiles(g,c));
        if ~isfile(file), error('Missing input file: %s',file); end
        summary{g,c} = local_read_summary(file,SHEET,MODEL_COLUMN, ...
            FREQUENCY_COLUMN,EXCEEDANCE_COLUMN,MODEL_NAMES,SUM_TOLERANCE);
        fprintf('%s | %s: %s\n',GROUP_LABELS(g),CONDITION_LABELS(c),file);
    end
end
% Select ALL winners before exporting any figures (fail early on ties).
winningValues = nan(2,2,2); winningIndices = nan(2,2,2);
for c = 1:2
    for metric = 1:2
        for g = 1:2
            values = summary{g,c}(:,metric);
            maximum = max(values);
            tied = find(abs(values-maximum) <= TIE_TOLERANCE);
            if numel(tied) ~= 1
                error('Tied maximum for %s | %s | %s: %s', ...
                    GROUP_LABELS(g),CONDITION_LABELS(c),METRIC_LABELS(metric), ...
                    strjoin(MODEL_NAMES(tied),', '));
            end
            winningValues(g,c,metric) = maximum;
            winningIndices(g,c,metric) = tied;
        end
    end
end

%% FOUR SEPARATE FIGURES AND WINNER SUMMARY
winners = table(strings(0,1),strings(0,1),strings(0,1),strings(0,1), ...
    zeros(0,1),strings(0,1),'VariableNames', ...
    {'Group','Condition','Metric','Winning_model','Value','Input_file'});
metricTokens = ["Frequency","Exceedance"];
for c = 1:2
    for metric = 1:2
        idx = winningIndices(:,c,metric);
        values = winningValues(:,c,metric);
        labels = MODEL_NAMES(idx); textures = MODEL_TEXTURES(idx);
        fig = local_plot_two_bars(values,labels,textures,GROUP_COLORS(:,:,c), ...
            GROUP_LABELS,CONDITION_LABELS(c),METRIC_LABELS(metric),style);
        base = sprintf('BMS_Condition%d_Winner_%s',c,metricTokens(metric));
        exportgraphics(fig,fullfile(outdir,[base,'.png']),'Resolution',png_dpi);
        exportgraphics(fig,fullfile(outdir,[base,'.pdf']),'ContentType','vector');
        for g = 1:2
            winners(end+1,:) = {GROUP_LABELS(g),CONDITION_LABELS(c), ...
                METRIC_LABELS(metric),MODEL_NAMES(idx(g)),values(g),inputFiles(g,c)};
        end
    end
end
writetable(winners,fullfile(outdir,'BMS_Winners.csv'));
save(fullfile(outdir,'BMS_Winner_Summaries.mat'),'summary','winners', ...
    'winningValues','winningIndices','inputFiles','inputDir','GROUP_LABELS', ...
    'CONDITION_LABELS','MODEL_NAMES','MODEL_TEXTURES','MODEL_COLUMN', ...
    'FREQUENCY_COLUMN','EXCEEDANCE_COLUMN','METRIC_LABELS','SHEET', ...
    'SUM_TOLERANCE','TIE_TOLERANCE','style','GROUP_COLORS','png_dpi');
disp(winners);
fprintf('Saved BMS winner figures and summaries in: %s\n',outdir);

%% LOCAL HELPERS
function values = local_read_summary(file,sheet,modelCol,freqCol,excCol,modelNames,tolerance)
    T = readtable(file,'Sheet',sheet,'VariableNamingRule','preserve');
    required = [modelCol,freqCol,excCol];
    if ~all(ismember(required,string(T.Properties.VariableNames)))
        error('Required columns missing in %s. Expected: %s',file,strjoin(required,', '));
    end
    names = lower(strtrim(string(T.(char(modelCol)))));
    expected = lower(strtrim(modelNames(:)));
    if height(T) ~= numel(expected) || any(ismissing(names)) || ...
            numel(unique(names)) ~= numel(names)
        error('Expected exactly one row per candidate model in %s.',file);
    end
    [found,idx] = ismember(expected,names);
    if ~all(found), error('Model names do not match MODEL_NAMES in %s.',file); end
    frequency = local_probability_column(T.(char(freqCol)),file,freqCol);
    exceedance = local_probability_column(T.(char(excCol)),file,excCol);
    values = [frequency(idx),exceedance(idx)];
    if any(abs(sum(values,1)-1) > tolerance)
        error('Model probabilities must sum to approximately 1 for each metric in %s.',file);
    end
end

function x = local_probability_column(raw,file,column)
    if isnumeric(raw), x = double(raw);
    else, x = str2double(strtrim(string(raw))); end
    x = x(:);
    if any(~isfinite(x) | x < 0 | x > 1)
        error('Column %s in %s must contain finite probabilities in [0,1].',column,file);
    end
end

function fig = local_plot_two_bars(values,labels,textures,colors,groups,condition,metric,style)
    fig = figure('Color','w','Units','pixels','Position',[150 150 850 650]);
    ax = axes(fig); hold(ax,'on');
    x = [0.75 1.70]; handles = gobjects(2,1);
    for g = 1:2
        handles(g) = bar(ax,x(g),values(g),style.barWidth, ...
            'FaceColor',colors(g,:),'EdgeColor',style.outlineColor, ...
            'LineWidth',style.barLineWidth);
        local_texture(ax,x(g)-style.barWidth/2,x(g)+style.barWidth/2, ...
            values(g),textures(g),style);
        % Redraw outline over textures; keep it out of the legend.
        plot(ax,[x(g)-style.barWidth/2,x(g)-style.barWidth/2, ...
            x(g)+style.barWidth/2,x(g)+style.barWidth/2], ...
            [0,values(g),values(g),0],'Color',style.outlineColor, ...
            'LineWidth',style.barLineWidth,'HandleVisibility','off');
    end
    ax.XTick = x; ax.XTickLabel = cellstr(labels);
    ax.FontSize = style.tickSize; ax.LineWidth = style.axisLineWidth;
    ax.TickDir = 'out'; ax.Box = 'off';
    xlim(ax,[0.35 2.10]); ylim(ax,[0 1]); ax.YTick = 0:0.2:1;
    xlabel(ax,'Winning model','FontSize',style.labelSize);
    ylabel(ax,metric,'FontSize',style.labelSize);
    lgd = legend(ax,handles,cellstr(groups),'Location','northoutside', ...
        'Orientation','horizontal','Box','off','FontSize',style.legendSize);
    lgd.Title.String = char(condition); lgd.AutoUpdate = 'off';
end

function local_texture(ax,left,right,height,kind,style)
    if height <= 0, return; end
    args = {'Color',style.hatchColor,'LineWidth',style.hatchLineWidth, ...
            'HandleVisibility','off'};
    switch kind
        case "horizontal"
            for y = style.horizontalGap:style.horizontalGap:height
                plot(ax,[left right],[y y],args{:});
            end
        case "vertical"
            for x = left+style.verticalGap:style.verticalGap:right
                plot(ax,[x x],[0 height],args{:});
            end
        case "diagonal"
            % Lines y = (x-left) + intercept, clipped to the bar rectangle.
            width = right-left;
            for intercept = -width:style.diagonalGap:height
                start = max(0,-intercept);
                stop = min(width,height-intercept);
                if stop > start
                    plot(ax,[left+start left+stop], ...
                        [start+intercept stop+intercept],args{:});
                end
            end
        otherwise
            error('Unknown model texture: %s',kind);
    end
end
