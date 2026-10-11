%% SKIN CONDUCTANCE RESPONSE ANALYSIS: TWO CONDITIONS x THREE LEVELS
% Author: Daniyal, University of Melbourne (original analysis).
% Generalized version prepared for public archiving.
%
% REQUIREMENTS: MATLAB R2020b or later and Statistics and Machine Learning
% Toolbox. The helper functions are included below.
%
% INPUT: Two MAT files with participant-level SCR summaries. Variable paths
% are configurable below (including nested paths such as peaks.HP).
% Each of the six variables must be a numeric vector. All vectors MUST refer
% to the same participants in the same order. Positional truncation cannot
% establish participant identity. Verify this alignment before running.
% S1 represents Controllable and S2 represents Uncontrollable throughout.
% HP/MP/UP = highly predictable/moderately predictable/unpredictable blocks.
%
% PREPROCESSING: This script expects SCR values already square-root
% transformed and range-corrected. It does not apply these transformations.
% By default, retain the first minimum-length N entries from every vector,
% reproducing the source script. Disable truncation to require equal lengths.
% Optionally set values outside mean +/- 3 sample SD to NaN separately in
% each condition x predictability cell. This is a single-pass procedure.
% Nonfinite values are treated as missing. Complete cases across all six
% cells are used consistently for figures, summaries and statistical tests.
%
%
% OUTPUT: PNG (600 dpi), vector PDF, Excel statistics and MAT results.
% Y-axis defaults to 0-1. Set FIXED_Y_AXIS=false for values on another scale.
% Participant labels below are row indices, not verified participant IDs.
% MATLAB runtime validation against the original data has not been performed.
% Author: Daniyal Rajput, University of Melbourne. Written by the author.


clear; clc; close all;
rng(1,'twister'); % Reproducible plotting jitter.

%% USER CONFIGURATION
inputFiles = struct('S1','scr_condition_1.mat','S2','scr_condition_2.mat');
% Edit these paths to match your MAT-file structures.
variablePathsS1 = ["peak_HP","peak_MP","peak_UP"];
variablePathsS2 = ["peaks.HP","peaks.MP","peaks.UP"];
TRUNCATE_TO_COMMON_N = true; % Requires verified participant order.
DO_3SD_REMOVE = true;
FIXED_Y_AXIS = true;
outdir = fullfile(pwd,'scr_outputs');
png_dpi = 600;
conditionLabels = ["Controllable","Uncontrollable"];
predLabels = ["HP","MP","UP"];
colors = [0.00 0.25 0.55;0.85 0.33 0.00];

%% OUTPUT AND LOG
if ~isfolder(outdir)
    [ok,msg] = mkdir(outdir);
    if ~ok, error('Cannot create output directory: %s',msg); end
end
logFile = fullfile(outdir,'SCR_RunLog.txt');
if isfile(logFile), delete(logFile); end
diary(logFile);
fprintf('SCR analysis | %s\nOutput: %s\n',datestr(now),outdir);
fprintf('Truncation=%d | Outlier removal=%d | Fixed Y-axis=%d\n', ...
    TRUNCATE_TO_COMMON_N,DO_3SD_REMOVE,FIXED_Y_AXIS);

%% LOAD AND CHECK INPUTS
assert(isfile(inputFiles.S1),'Missing input: %s',inputFiles.S1);
assert(isfile(inputFiles.S2),'Missing input: %s',inputFiles.S2);
scr_s1 = load(inputFiles.S1); scr_s2 = load(inputFiles.S2);
rawVectors = cell(1,6);
for k = 1:3
    rawVectors{k} = local_read_vector(scr_s1,variablePathsS1(k));
    rawVectors{k+3} = local_read_vector(scr_s2,variablePathsS2(k));
end
lengths = cellfun(@numel,rawVectors);
fprintf('Vector lengths [HP_S1 MP_S1 UP_S1 HP_S2 MP_S2 UP_S2]: %s\n',mat2str(lengths));
if ~TRUNCATE_TO_COMMON_N && numel(unique(lengths)) ~= 1
    error('Vector lengths differ; align participant IDs before analysis.');
end
Ncommon = min(lengths);
if Ncommon < 3, error('At least three aligned participant rows are required.'); end
rawMatrix = nan(Ncommon,6);
for k = 1:6, rawMatrix(:,k) = rawVectors{k}(1:Ncommon); end
fprintf('Rows removed by positional truncation per vector: %s\n',mat2str(lengths-Ncommon));

%% OUTLIER REMOVAL AND COMPLETE CASES
cleanMatrix = rawMatrix;
cleanMatrix(~isfinite(cleanMatrix)) = NaN;
cellConditions = repelem(conditionLabels(:),3);
cellPredictability = repmat(predLabels(:),2,1);
outlierReport = table(cellConditions,cellPredictability,zeros(6,1), ...
    zeros(6,1),zeros(6,1),nan(6,1),nan(6,1), ...
    'VariableNames',{'Control','Predictability','N_before','N_removed', ...
                    'N_after','Lower_bound','Upper_bound'});
for k = 1:6
    [cleanMatrix(:,k),info] = local_clip3sd_to_nan(cleanMatrix(:,k),DO_3SD_REMOVE);
    outlierReport.N_before(k) = info.n_before;
    outlierReport.N_removed(k) = info.n_out;
    outlierReport.N_after(k) = info.n_after;
    outlierReport.Lower_bound(k) = info.lo;
    outlierReport.Upper_bound(k) = info.hi;
end
isComplete = all(isfinite(cleanMatrix),2);
Subject = find(isComplete); % Original aligned row indices.
Y = cleanMatrix(isComplete,:); Nfinal = size(Y,1);
fprintf('Complete cases: %d/%d; excluded=%d\n',Nfinal,Ncommon,Ncommon-Nfinal);
disp(outlierReport);
if Nfinal < 3, error('Fewer than three complete cases remain.'); end
inclusionReport = table((1:Ncommon)',isComplete, ...
    'VariableNames',{'Aligned_row','Included_complete_case'});

%% FIGURE: BOX PLOTS AND PARTICIPANT POINTS
fig = figure('Color','w','Units','pixels','Position',[220 240 1200 520]);
ax = axes(fig); hold(ax,'on');
centers = 1:3; offset = 0.18; boxWidth = 0.28;
dotJitter = (boxWidth/2)*0.85;
legendHandles = gobjects(2,1);
for c = 1:2
    for p = 1:3
        x = centers(p) + (2*c-3)*offset;
        y = Y(:,(c-1)*3+p);
        b = boxchart(ax,x*ones(size(y)),y,'BoxWidth',boxWidth, ...
            'BoxFaceColor',colors(c,:),'BoxFaceAlpha',0.28, ...
            'MarkerStyle','none','LineWidth',1.2);
        jitter = (rand(numel(y),1)-0.5)*2*dotJitter;
        scatter(ax,x+jitter,y,30,colors(c,:),'filled', ...
            'MarkerEdgeColor','k','MarkerFaceAlpha',0.85);
        if p == 1, legendHandles(c) = b; end
    end
end
ax.XTick = centers; ax.XTickLabel = cellstr(predLabels);
ax.FontSize = 18; ax.LineWidth = 1.6; ax.TickDir = 'out'; ax.Box = 'off';
xlim(ax,[0.5 3.5]);
if FIXED_Y_AXIS
    if any(Y(:) < 0 | Y(:) > 1)
        error('Values fall outside 0-1. Check preprocessing or disable FIXED_Y_AXIS.');
    end
    ylim(ax,[0 1]); ax.YTick = 0:0.2:1;
    ax.YTickLabel = compose('%.1f',ax.YTick);
end
xlabel(ax,'Predictability','FontSize',20,'FontWeight','bold');
ylabel(ax,'SCR (square-root transformed, range-corrected)', ...
    'FontSize',18,'FontWeight','bold');
legend(ax,legendHandles,cellstr(conditionLabels),'Location','northoutside', ...
    'Orientation','horizontal','Box','off','FontSize',15);
fig_png = fullfile(outdir,'SCR_BoxScatter.png');
fig_pdf = fullfile(outdir,'SCR_BoxScatter_vector.pdf');
exportgraphics(fig,fig_png,'Resolution',png_dpi);
exportgraphics(fig,fig_pdf,'ContentType','vector');

%% DESCRIPTIVES
means = mean(Y,1)'; sems = std(Y,0,1)'/sqrt(Nfinal);
desc = table(cellConditions,cellPredictability,repmat(Nfinal,6,1),means,sems, ...
    'VariableNames',{'Control','Predictability','N','Mean','SEM'});
disp(desc);

%% TWO x THREE REPEATED-MEASURES ANOVA
responseNames = {'HP_S1','MP_S1','UP_S1','HP_S2','MP_S2','UP_S2'};
Twide = [table(Subject),array2table(Y,'VariableNames',responseNames)];
Within = table(categorical(cellConditions),categorical(cellPredictability), ...
    'VariableNames',{'Control','Predictability'});
rm = fitrm(Twide,'HP_S1-UP_S2 ~ 1','WithinDesign',Within);
ranovatbl_raw = ranova(rm,'WithinModel','Control*Predictability');
rn = string(ranovatbl_raw.Properties.RowNames);
ranovatbl = addvars(ranovatbl_raw,rn,'Before',1,'NewVariableNames','Effect');
ranovatbl.Properties.RowNames = {};
Eta_p2 = nan(height(ranovatbl),1);
for i = 1:height(ranovatbl)
    eff = rn(i);
    if startsWith(eff,"Error") || eff == "(Intercept)", continue; end
    parts = split(eff,':'); parts = parts(parts ~= "(Intercept)");
    errName = "Error(" + strjoin(parts,':') + ")";
    j = find(rn == errName,1);
    if ~isempty(j)
        totalSS = ranovatbl.SumSq(i) + ranovatbl.SumSq(j);
        if totalSS > 0, Eta_p2(i) = ranovatbl.SumSq(i)/totalSS; end
    end
end
ranovatbl.Eta_p2 = Eta_p2;
isEffect = ~startsWith(rn,"Error") & rn ~= "(Intercept)";
effect_summary = ranovatbl(isEffect,:); % Retain all p-value correction columns.
disp(effect_summary);

%% POSTHOCS: SOURCE MODEL-BASED BONFERRONI COMPARISONS
mc_pred = multcompare(rm,'Predictability','By','Control','ComparisonType','bonferroni');
mc_ctrl = multcompare(rm,'Control','By','Predictability','ComparisonType','bonferroni');
if iscell(mc_pred), mc_pred = vertcat(mc_pred{:}); end
if iscell(mc_ctrl), mc_ctrl = vertcat(mc_ctrl{:}); end

%% PAIRED EFFECT SIZES: PREDICTABILITY WITHIN EACH CONDITION
pairs = [1 2;1 3;2 3];
dz_tbl = table(cellConditions,strings(6,1),nan(6,1), ...
    'VariableNames',{'Control','Comparison','Cohens_dz'});
for c = 1:2
    for k = 1:3
        row = (c-1)*3+k;
        a = (c-1)*3+pairs(k,1); b = (c-1)*3+pairs(k,2);
        differences = Y(:,a)-Y(:,b); sdDifference = std(differences);
        dz_tbl.Comparison(row) = predLabels(pairs(k,1)) + " vs " + predLabels(pairs(k,2));
        % Undefined standardized effect when paired differences have zero SD.
        if sdDifference > 0
            dz_tbl.Cohens_dz(row) = mean(differences)/sdDifference;
        end
    end
end

%% S1-S2 CORRELATIONS (UNADJUSTED P-VALUES, AS IN SOURCE)
corr_tbl = table(predLabels(:),nan(3,1),nan(3,1),repmat(Nfinal,3,1), ...
    'VariableNames',{'Predictability','r','p_raw','N'});
for p = 1:3
    [r,pvalue] = corr(Y(:,p),Y(:,p+3),'Type','Pearson','Rows','complete');
    corr_tbl.r(p) = r; corr_tbl.p_raw(p) = pvalue;
end

%% SAVE RESULTS
stats_xlsx = fullfile(outdir,'SCR_Statistics.xlsx');
mat_out = fullfile(outdir,'SCR_AllOutputs.mat');
writetable(desc,stats_xlsx,'Sheet','Descriptives');
writetable(effect_summary,stats_xlsx,'Sheet','RMANOVA_effects');
writetable(ranovatbl,stats_xlsx,'Sheet','RMANOVA_full');
writetable(mc_pred,stats_xlsx,'Sheet','Posthoc_Predictability_bonf');
writetable(mc_ctrl,stats_xlsx,'Sheet','Posthoc_Control_bonf');
writetable(dz_tbl,stats_xlsx,'Sheet','Pairwise_CohensDZ');
writetable(corr_tbl,stats_xlsx,'Sheet','Correlations_S1_S2');
writetable(outlierReport,stats_xlsx,'Sheet','Outlier_report');
writetable(inclusionReport,stats_xlsx,'Sheet','Inclusion_report');
save(mat_out,'inputFiles','variablePathsS1','variablePathsS2','rawVectors', ...
    'rawMatrix','cleanMatrix','Y','Subject','Ncommon','Nfinal','isComplete', ...
    'outlierReport','inclusionReport','Twide','Within','rm','ranovatbl_raw', ...
    'ranovatbl','effect_summary','mc_pred','mc_ctrl','dz_tbl','corr_tbl','desc', ...
    'TRUNCATE_TO_COMMON_N','DO_3SD_REMOVE','FIXED_Y_AXIS','conditionLabels', ...
    'predLabels','outdir','fig_png','fig_pdf','png_dpi');
fprintf('Saved:\n%s\n%s\n%s\n%s\n',fig_png,fig_pdf,stats_xlsx,mat_out);
diary off;

%% LOCAL HELPERS
function x = local_read_vector(data,path)
    keys = split(path,'.'); value = data;
    for k = 1:numel(keys)
        key = char(keys(k));
        if ~isstruct(value) || ~isscalar(value) || ~isfield(value,key)
            error('Missing or invalid MAT variable path: %s',path);
        end
        value = value.(key);
    end
    if ~isnumeric(value) || ~isreal(value) || ~isvector(value)
        error('MAT variable %s must be a real numeric vector.',path);
    end
    x = double(value(:));
end

function [x,info] = local_clip3sd_to_nan(x,doRemove)
    x = x(:); x(~isfinite(x)) = NaN;
    valid = isfinite(x); n = sum(valid);
    info = struct('n_before',n,'n_out',0,'n_after',n,'lo',NaN,'hi',NaN);
    if n < 3 || ~doRemove, return; end
    mu = mean(x(valid)); sd = std(x(valid));
    info.lo = mu-3*sd; info.hi = mu+3*sd;
    outside = valid & (x < info.lo | x > info.hi);
    x(outside) = NaN;
    info.n_out = sum(outside); info.n_after = sum(isfinite(x));
end
