%% REACTION-TIME ANALYSIS: TWO GROUPS x TWO CONDITIONS x THREE LEVELS
% Author: Daniyal, University of Melbourne (original analysis).
% Generalized version prepared for public archiving.
%
% REQUIREMENTS: MATLAB R2020b or later with Statistics and Machine Learning
% Toolbox. All local helpers are included in this file.
%
% INPUT: Four Excel workbooks, one per group and condition. Each worksheet
% represents one participant, has a header row, and lists trials in their
% original order. Do not include summary worksheets. Match participants
% within each group using the uppercase text before the FIRST underscore:
% P001_S1 and P001_S2 both become P001. Participant IDs must therefore not
% contain underscores before a session suffix. Duplicate normalized IDs
% cause an error instead of silently selecting one worksheet.
%
% RT values must be milliseconds. Edit the filenames, column indices and
% block lists below. Block labels are exact matches after whitespace trimming.
% The source block selection is retained; it does not include every task
% block. Change it only if you intend to change the selected data.
%
% PREPROCESSING (retains the source RT analysis order):
% 1. Select first N_FIRST_TRIALS rows of each specified block in row order.
% 2. Omit missing, nonfinite, or out-of-range RTs within those rows; do not
%    replace them with later trials. RT_MIN and RT_MAX are inclusive.
% 3. Average valid RTs per block, then average available block means equally.
%    A missing block is omitted; no valid block means produces NaN.
% 4. Match sessions; require all six cells before estimating outliers.
% 5. Optionally set values beyond group-cell mean +/- 3 SD to NaN once,
%    then require all six cells again.
%
% STATISTICS: 2 x 2 x 3 mixed repeated-measures ANOVA; Welch between-group
% and paired within-group t-tests. Separate Bonferroni families: 6 group
% comparisons, 6 condition comparisons, 12 predictability comparisons.
% ANOVA_full exports all ranova p-value variants. Choose/report appropriate
% sphericity correction separately. ANOVA_between exports the between-group
% model. Partial eta squared uses the corresponding ANOVA error term.
%
% OUTPUT: 2 x 3 figure PNG and vector PDF, Excel statistics and retained IDs,
% MAT analysis objects, and run log. No participant data accompany this code.
% The code has not been executed in MATLAB against the original workbooks.
% Author: Daniyal Rajput, University of Melbourne. Written by the author.

clear; clc; close all;
rng(1,'twister'); % Reproducible plotting jitter.

%% USER CONFIGURATION
groupAFiles = struct('S1','group_a_condition_1.xlsx', ...
                     'S2','group_a_condition_2.xlsx');
groupBFiles = struct('S1','group_b_condition_1.xlsx', ...
                     'S2','group_b_condition_2.xlsx');
blockCol = 2;
groupARTcol = 7;
groupBRTcol = 4;
HP_blocks = ["Block1","Block10"];
MP_blocks = ["Block4","Block7"];
UP_blocks = ["Block2","Block6"];
RT_MIN = 100;
RT_MAX = 800;
N_FIRST_TRIALS = 25;
DO_3SD_REMOVE = true;
DO_COMPLETE_CASE = true; % Required for this ANOVA workflow.
BALANCE_GROUPS = true;
outdir = fullfile(pwd,'rt_outputs');
png_dpi = 600;
colGroupA = [0.05 0.20 0.55];
colGroupB = [0.60 0.10 0.10];
conditionColors = [0.60 0.78 1.00;1.00 0.72 0.45];
boxWidth = 0.35;
dotJitter = (boxWidth/2)*0.85;
assert(isfinite(RT_MIN) && isfinite(RT_MAX) && RT_MIN < RT_MAX, ...
    'RT limits must be finite and ascending.');
assert(isscalar(N_FIRST_TRIALS) && isfinite(N_FIRST_TRIALS) && ...
    N_FIRST_TRIALS >= 1 && N_FIRST_TRIALS == floor(N_FIRST_TRIALS), ...
    'N_FIRST_TRIALS must be a positive integer.');

%% =============================== OUTPUT + LOG ===============================
if ~exist(outdir,'dir')
    [ok,msg] = mkdir(outdir);
    if ~ok, error('Cannot create output directory:\n%s\nReason: %s', outdir, msg); end
end
log_txt = fullfile(outdir,'Figure2_RT_GroupAvsGroupB_RunLog.txt');
if exist(log_txt,'file'), delete(log_txt); end
diary(log_txt);
fprintf('============================================================\n');
fprintf('REACTION TIME Group A vs Group B (2x2x3) | Output: %s\n', outdir);
fprintf('Group A: %s | %s\n', groupAFiles.S1, groupAFiles.S2);
fprintf('Group B:    %s | %s\n', groupBFiles.S1, groupBFiles.S2);
fprintf('Cols: blockCol=%d | groupARTcol=%d | groupBRTcol=%d\n', blockCol, groupARTcol, groupBRTcol);
fprintf('Blocks: HP=%s | MP=%s | UP=%s\n', strjoin(HP_blocks,','), strjoin(MP_blocks,','), strjoin(UP_blocks,','));
fprintf('3SD: DO_3SD_REMOVE=%d | DO_COMPLETE_CASE=%d\n', DO_3SD_REMOVE, DO_COMPLETE_CASE);
fprintf('RT selection: first %d trials/block; inclusive range %g-%g ms\n',N_FIRST_TRIALS,RT_MIN,RT_MAX);
fprintf('Timestamp: %s\n', datestr(now));
fprintf('============================================================\n\n');
%% =============================== 1) READ REACTION TIME PER SHEET ===============================
H_S1_raw = local_read_rt_excel(groupAFiles.S1, blockCol, groupARTcol, "group_a", HP_blocks, MP_blocks, UP_blocks, RT_MIN, RT_MAX, N_FIRST_TRIALS);
H_S2_raw = local_read_rt_excel(groupAFiles.S2, blockCol, groupARTcol, "group_a", HP_blocks, MP_blocks, UP_blocks, RT_MIN, RT_MAX, N_FIRST_TRIALS);
P_S1_raw = local_read_rt_excel(groupBFiles.S1,    blockCol, groupBRTcol,    "group_b",    HP_blocks, MP_blocks, UP_blocks, RT_MIN, RT_MAX, N_FIRST_TRIALS);
P_S2_raw = local_read_rt_excel(groupBFiles.S2,    blockCol, groupBRTcol,    "group_b",    HP_blocks, MP_blocks, UP_blocks, RT_MIN, RT_MAX, N_FIRST_TRIALS);
%% =============================== 2) WITHIN-GROUP MATCH (S1 vs S2) ===============================
[H, msgH] = local_match_S1S2_within_group(H_S1_raw, H_S2_raw, "Group A");
[P, msgP] = local_match_S1S2_within_group(P_S1_raw, P_S2_raw, "Group B");
fprintf('\n--- Within-group matching ---\n%s\n%s\n', msgH, msgP);
% Initial complete-case filtering precedes outlier estimation in the RT source.
H = local_complete_cases(H);
P = local_complete_cases(P);
fprintf('Initial complete cases: Group A=%d | Group B=%d\n',numel(H.id),numel(P.id));
%% =============================== 2.5) ±3 SD OUTLIER REMOVAL (CELL-WISE) ===============================
outlier_report = table('Size',[0 6], ...
    'VariableTypes', {'string','string','string','double','double','double'}, ...
    'VariableNames', {'Group','Control','Predictability','N_before','N_removed','N_after'});
if DO_3SD_REMOVE
    fprintf('\n--- ±3 SD outlier removal (cell-wise) ---\n');
    rm3sd = @(x) local_rm3sd_inline(x);
    [H.HP_S1, nb,nr,na] = rm3sd(H.HP_S1); outlier_report(end+1,:) = {"Group A","Controllable","HP",nb,nr,na};
    [H.MP_S1, nb,nr,na] = rm3sd(H.MP_S1); outlier_report(end+1,:) = {"Group A","Controllable","MP",nb,nr,na};
    [H.UP_S1, nb,nr,na] = rm3sd(H.UP_S1); outlier_report(end+1,:) = {"Group A","Controllable","UP",nb,nr,na};
    [H.HP_S2, nb,nr,na] = rm3sd(H.HP_S2); outlier_report(end+1,:) = {"Group A","Uncontrollable","HP",nb,nr,na};
    [H.MP_S2, nb,nr,na] = rm3sd(H.MP_S2); outlier_report(end+1,:) = {"Group A","Uncontrollable","MP",nb,nr,na};
    [H.UP_S2, nb,nr,na] = rm3sd(H.UP_S2); outlier_report(end+1,:) = {"Group A","Uncontrollable","UP",nb,nr,na};
    [P.HP_S1, nb,nr,na] = rm3sd(P.HP_S1); outlier_report(end+1,:) = {"Group B","Controllable","HP",nb,nr,na};
    [P.MP_S1, nb,nr,na] = rm3sd(P.MP_S1); outlier_report(end+1,:) = {"Group B","Controllable","MP",nb,nr,na};
    [P.UP_S1, nb,nr,na] = rm3sd(P.UP_S1); outlier_report(end+1,:) = {"Group B","Controllable","UP",nb,nr,na};
    [P.HP_S2, nb,nr,na] = rm3sd(P.HP_S2); outlier_report(end+1,:) = {"Group B","Uncontrollable","HP",nb,nr,na};
    [P.MP_S2, nb,nr,na] = rm3sd(P.MP_S2); outlier_report(end+1,:) = {"Group B","Uncontrollable","MP",nb,nr,na};
    [P.UP_S2, nb,nr,na] = rm3sd(P.UP_S2); outlier_report(end+1,:) = {"Group B","Uncontrollable","UP",nb,nr,na};
    disp(outlier_report);
end
if DO_COMPLETE_CASE
        okH = isfinite(H.HP_S1) & isfinite(H.MP_S1) & isfinite(H.UP_S1) & ...
              isfinite(H.HP_S2) & isfinite(H.MP_S2) & isfinite(H.UP_S2);
        okP = isfinite(P.HP_S1) & isfinite(P.MP_S1) & isfinite(P.UP_S1) & ...
              isfinite(P.HP_S2) & isfinite(P.MP_S2) & isfinite(P.UP_S2);
        nH0 = numel(H.id); nP0 = numel(P.id);
        H = local_subset_group(H, find(okH));
        P = local_subset_group(P, find(okP));
        fprintf('Complete-case after 3SD: Group A %d -> %d | Group B %d -> %d\n', nH0, numel(H.id), nP0, numel(P.id));
end
if ~DO_COMPLETE_CASE
    error('This ANOVA workflow requires DO_COMPLETE_CASE=true.');
end
%% =============================== 3) BALANCE GROUPS (same N) ===============================
% BALANCE_GROUPS is configured above.
N_H = numel(H.id);
N_P = numel(P.id);
N   = min(N_H, N_P);
if N < 3
    error('Too few matched subjects after cleanup. Group A=%d, Group B=%d', N_H, N_P);
end
[~, idxH] = sort(H.id);
[~, idxP] = sort(P.id);
if BALANCE_GROUPS
    H = local_subset_group(H, idxH(1:N));
    P = local_subset_group(P, idxP(1:N));
else
    H = local_subset_group(H, idxH);
    P = local_subset_group(P, idxP);
end
fprintf('Retained: Group A=%d | Group B=%d\n', numel(H.id), numel(P.id));
fprintf('Available complete cases: Group A=%d | Group B=%d; balancing=%d\n', N_H, N_P, BALANCE_GROUPS);
%% =============================== 4) DESCRIPTIVES ===============================
meanSEM = @(x) [mean(x,'omitnan'), std(x,'omitnan')/sqrt(sum(~isnan(x)))];
desc = table(strings(0,1), strings(0,1), strings(0,1), zeros(0,1), zeros(0,1), ...
    'VariableNames', {'Group','Control','Predictability','MeanRT_ms','SEM_ms'});
desc = [desc; local_desc_rows("Group A","Controllable",   H.HP_S1, H.MP_S1, H.UP_S1, meanSEM)];
desc = [desc; local_desc_rows("Group A","Uncontrollable", H.HP_S2, H.MP_S2, H.UP_S2, meanSEM)];
desc = [desc; local_desc_rows("Group B","Controllable",      P.HP_S1, P.MP_S1, P.UP_S1, meanSEM)];
desc = [desc; local_desc_rows("Group B","Uncontrollable",    P.HP_S2, P.MP_S2, P.UP_S2, meanSEM)];
disp('===== Descriptives (RT ms, Mean ± SEM) =====');
disp(desc);
%% FIGURE: CONDITIONS IN ROWS, PREDICTABILITY IN COLUMNS
fig = figure('Color','w','Units','pixels','Position',[100 100 1500 760]);
tl = tiledlayout(2,3,'TileSpacing','compact','Padding','compact');
fields = {'HP_S1','MP_S1','UP_S1';'HP_S2','MP_S2','UP_S2'};
predTitles = {'Highly predictable','Moderately predictable','Unpredictable'};
conditionTitles = {'Controllable','Uncontrollable'};
allRT = [H.HP_S1;H.MP_S1;H.UP_S1;H.HP_S2;H.MP_S2;H.UP_S2; ...
         P.HP_S1;P.MP_S1;P.UP_S1;P.HP_S2;P.MP_S2;P.UP_S2];
ylo = min(allRT); yhi = max(allRT);
pad = max(1,0.08*(yhi-ylo));
for r = 1:2
    for c = 1:3
        ax = nexttile(tl); hold(ax,'on');
        values = {H.(fields{r,c}), P.(fields{r,c})};
        colors = {colGroupA,colGroupB};
        for g = 1:2
            y = values{g};
            boxchart(ax,g*ones(size(y)),y,'BoxWidth',boxWidth, ...
                'BoxFaceColor',conditionColors(r,:),'BoxFaceAlpha',0.22, ...
                'MarkerStyle','none','LineWidth',1.2);
            jitter = (rand(numel(y),1)-0.5)*2*dotJitter;
            scatter(ax,g+jitter,y,40,colors{g},'filled', ...
                'MarkerEdgeColor','k','MarkerFaceAlpha',0.9);
        end
        xlim(ax,[0.5 2.5]); ylim(ax,[ylo-pad yhi+pad]);
        ax.XTick = [1 2]; ax.XTickLabel = {'Group A','Group B'};
        ax.FontSize = 15; ax.LineWidth = 1.6;
        ax.Box = 'off'; ax.TickDir = 'out';
        title(ax,sprintf('%s | %s',conditionTitles{r},predTitles{c}), ...
            'FontSize',17,'FontWeight','bold');
        if c == 1, ylabel(ax,'Reaction time (ms)','FontSize',18); end
        if r == 1 && c == 3
            d1 = plot(ax,nan,nan,'s','MarkerFaceColor',conditionColors(1,:), ...
                'MarkerEdgeColor','none');
            d2 = plot(ax,nan,nan,'s','MarkerFaceColor',conditionColors(2,:), ...
                'MarkerEdgeColor','none');
            d3 = plot(ax,nan,nan,'o','MarkerFaceColor',colGroupA,'MarkerEdgeColor','k');
            d4 = plot(ax,nan,nan,'o','MarkerFaceColor',colGroupB,'MarkerEdgeColor','k');
            lgd = legend(ax,[d1 d2 d3 d4], ...
                {'Controllable','Uncontrollable','Group A','Group B'}, ...
                'Orientation','horizontal','Box','off','FontSize',13);
            lgd.Layout.Tile = 'north'; lgd.AutoUpdate = 'off';
        end
    end
end
fig_png = fullfile(outdir,sprintf('RT_GroupAvsGroupB_FIRST%d_%ddpi.png',N_FIRST_TRIALS,png_dpi));
fig_pdf = fullfile(outdir,sprintf('RT_GroupAvsGroupB_FIRST%d_vector.pdf',N_FIRST_TRIALS));
exportgraphics(fig,fig_png,'Resolution',png_dpi);
exportgraphics(fig,fig_pdf,'ContentType','vector');
fprintf('Saved RT figure:\n%s\n%s\n',fig_png,fig_pdf);

%% =============================== 6) 2×2×3 MIXED RM ANOVA ===============================
T_H = table("H_"+H.id, categorical(repmat("Group A", numel(H.id),1)), ...
    H.HP_S1, H.MP_S1, H.UP_S1, H.HP_S2, H.MP_S2, H.UP_S2, ...
    'VariableNames', {'Subject','Group','HP_S1','MP_S1','UP_S1','HP_S2','MP_S2','UP_S2'});
T_P = table("P_"+P.id, categorical(repmat("Group B", numel(P.id),1)), ...
    P.HP_S1, P.MP_S1, P.UP_S1, P.HP_S2, P.MP_S2, P.UP_S2, ...
    'VariableNames', {'Subject','Group','HP_S1','MP_S1','UP_S1','HP_S2','MP_S2','UP_S2'});
Twide = [T_H; T_P];
Within = table( ...
    categorical({'Controllable';'Controllable';'Controllable';'Uncontrollable';'Uncontrollable';'Uncontrollable'}), ...
    categorical({'HP';'MP';'UP';'HP';'MP';'UP'}), ...
    'VariableNames', {'Control','Predictability'});
rm = fitrm(Twide, 'HP_S1-UP_S2 ~ Group', 'WithinDesign', Within);
ranovatbl = ranova(rm, 'WithinModel', 'Control*Predictability');
between_anova = anova(rm);
rn = string(ranovatbl.Properties.RowNames);
ranovatbl = addvars(ranovatbl, rn, 'Before', ranovatbl.Properties.VariableNames{1}, 'NewVariableNames','Effect');
ranovatbl.Properties.RowNames = {};
Eta_p2 = nan(height(ranovatbl),1);
for i = 1:height(ranovatbl)
    eff = string(ranovatbl.Effect(i));
    if startsWith(eff,"Error"), continue; end
    parts = split(eff, ':');
    withinParts = parts(parts ~= "Group" & parts ~= "(Intercept)");
    if isempty(withinParts)
        errName = "Error";
    else
        errName = "Error(" + strjoin(withinParts, ':') + ")";
    end
    idx_err = find(rn == errName, 1);
    if ~isempty(idx_err) && ismember("SumSq", ranovatbl.Properties.VariableNames)
        SS_eff = ranovatbl.SumSq(i);
        SS_err = ranovatbl.SumSq(idx_err);
        Eta_p2(i) = SS_eff / (SS_eff + SS_err);
    end
end
ranovatbl.Eta_p2 = Eta_p2;
isEffectRow = ~startsWith(string(ranovatbl.Effect), "Error") & string(ranovatbl.Effect) ~= "(Intercept)";
effect_summary = ranovatbl(isEffectRow, intersect(ranovatbl.Properties.VariableNames, {'Effect','DF','F','pValue','Eta_p2','SumSq'}));
disp('===== 2×2×3 MIXED ANOVA (RT) + ηp² =====');
disp(effect_summary);
%% =============================== 7) POSTHOCS (manual comparisons) ===============================
preds = ["HP","MP","UP"];
ctrls = ["Controllable","Uncontrollable"];
groups = ["Group A","Group B"];
getCell = @(G,C,PR) local_get_cell(H,P,G,C,PR);
between_tbl = table(strings(0,1), strings(0,1), zeros(0,1), zeros(0,1), zeros(0,1), zeros(0,1), ...
    'VariableNames', {'Control','Predictability','t','df','p_unc','p_bonf'});
for ci = 1:numel(ctrls)
    for pi = 1:numel(preds)
        C  = ctrls(ci);
        PR = preds(pi);
        yH = getCell("Group A", C, PR);
        yP = getCell("Group B",    C, PR);
        [~,p,~,st] = ttest2(yH, yP, 'Vartype','unequal'); % Welch
        between_tbl = [between_tbl; table(C,PR,st.tstat,st.df,p,NaN, ...
            'VariableNames',between_tbl.Properties.VariableNames)]; %#ok<AGROW>
    end
end
between_tbl.p_bonf = min(between_tbl.p_unc * 6, 1);
within_control_tbl = table(strings(0,1), strings(0,1), zeros(0,1), zeros(0,1), zeros(0,1), zeros(0,1), ...
    'VariableNames', {'Group','Predictability','t','df','p_unc','p_bonf'});
for gi = 1:numel(groups)
    for pi = 1:numel(preds)
        G  = groups(gi);
        PR = preds(pi);
        yS1 = getCell(G, "Controllable",   PR);
        yS2 = getCell(G, "Uncontrollable", PR);
        [~,p,~,st] = ttest(yS1, yS2); % paired
        within_control_tbl = [within_control_tbl; table(G,PR,st.tstat,st.df,p,NaN, ...
            'VariableNames',within_control_tbl.Properties.VariableNames)]; %#ok<AGROW>
    end
end
within_control_tbl.p_bonf = min(within_control_tbl.p_unc * 6, 1);
pairs = ["HP","MP"; "HP","UP"; "MP","UP"];
within_pred_tbl = table(strings(0,1), strings(0,1), strings(0,1), zeros(0,1), zeros(0,1), zeros(0,1), zeros(0,1), ...
    'VariableNames', {'Group','Control','Comparison','t','df','p_unc','p_bonf'});
for gi = 1:numel(groups)
    for ci = 1:numel(ctrls)
        G = groups(gi);
        C = ctrls(ci);
        for k = 1:size(pairs,1)
            A = pairs(k,1); B = pairs(k,2);
            yA = getCell(G,C,A);
            yB = getCell(G,C,B);
            [~,p,~,st] = ttest(yA,yB); % paired
            comp = A + " vs " + B;
            within_pred_tbl = [within_pred_tbl; table(G,C,comp,st.tstat,st.df,p,NaN, ...
                'VariableNames',within_pred_tbl.Properties.VariableNames)]; %#ok<AGROW>
        end
    end
end
within_pred_tbl.p_bonf = min(within_pred_tbl.p_unc * 12, 1);
disp('===== Posthoc BETWEEN (Group A vs Group B) per cell (Bonferroni) ====='); disp(between_tbl);
disp('===== Posthoc WITHIN CONTROL (S1 vs S2) per Group×Pred (Bonferroni) ====='); disp(within_control_tbl);
disp('===== Posthoc WITHIN PREDICTABILITY (Bonferroni) ====='); disp(within_pred_tbl);
%% =============================== 8) SAVE OUTPUTS ===============================
stats_xlsx = fullfile(outdir,sprintf('RT_GroupAvsGroupB_FIRST%d_STATS.xlsx',N_FIRST_TRIALS));
mat_out = fullfile(outdir,sprintf('RT_GroupAvsGroupB_FIRST%d_AllOutputs.mat',N_FIRST_TRIALS));
writetable(desc,           stats_xlsx, 'Sheet','Descriptives');
ids_tbl = Twide(:,{'Subject','Group'});
writetable(ids_tbl, stats_xlsx, 'Sheet','Retained_IDs');
if DO_3SD_REMOVE
    writetable(outlier_report, stats_xlsx, 'Sheet','OutlierReport_3SD');
end
writetable(ranovatbl,      stats_xlsx, 'Sheet','ANOVA_full');
writetable(between_anova, stats_xlsx, 'Sheet','ANOVA_between', 'WriteRowNames',true);
writetable(effect_summary, stats_xlsx, 'Sheet','ANOVA_effects_eta_p2');
writetable(between_tbl,    stats_xlsx, 'Sheet','Posthoc_Between');
writetable(within_control_tbl, stats_xlsx, 'Sheet','Posthoc_Within_Control');
writetable(within_pred_tbl,    stats_xlsx, 'Sheet','Posthoc_Within_Pred');
save(mat_out, ...
    'H_S1_raw','H_S2_raw','P_S1_raw','P_S2_raw','H','P','Twide','Within','rm', ...
    'ranovatbl','between_anova','effect_summary','desc','between_tbl','within_control_tbl','within_pred_tbl', ...
    'outlier_report','fig_png','fig_pdf','outdir', ...
    'groupAFiles','groupBFiles','groupARTcol','groupBRTcol','blockCol', ...
    'HP_blocks','MP_blocks','UP_blocks','RT_MIN','RT_MAX','N_FIRST_TRIALS', ...
    'DO_3SD_REMOVE','DO_COMPLETE_CASE','BALANCE_GROUPS');
fprintf('\n DONE — saved:\n%s\n%s\n%s\n%s\n', fig_png, fig_pdf, stats_xlsx, mat_out);
diary off;

%% LOCAL HELPERS
function S = local_read_rt_excel(file,blockCol,rtCol,~,hp,mp,up,rtMin,rtMax,nFirst)
    if ~isfile(file), error('Input workbook not found: %s',file); end
    sheets = string(sheetnames(file));
    base = upper(strtrim(extractBefore(sheets + "_","_")));
    if any(ismissing(base) | base == "") || numel(unique(base)) ~= numel(base)
        error('Empty or duplicate normalized participant IDs in %s.',file);
    end
    S = struct('id',base(:),'sheet',sheets(:), ...
        'HP',nan(numel(sheets),1),'MP',nan(numel(sheets),1),'UP',nan(numel(sheets),1));
    blockSets = {hp,mp,up}; names = {'HP','MP','UP'};
    for i = 1:numel(sheets)
        T = readtable(file,'Sheet',sheets(i),'VariableNamingRule','preserve');
        if width(T) < max(blockCol,rtCol)
            error('Insufficient columns in %s, sheet %s.',file,sheets(i));
        end
        blocks = strtrim(string(T{:,blockCol}));
        raw = T{:,rtCol};
        if isnumeric(raw) || islogical(raw)
            rt = double(raw);
        else
            text = strtrim(string(raw)); rt = str2double(text);
            bad = ~ismissing(text) & text ~= "" & isnan(rt) & lower(text) ~= "nan";
            if any(bad), error('Nonnumeric RT in %s, sheet %s.',file,sheets(i)); end
        end
        rt = rt(:); rt(~isfinite(rt) | rt < rtMin | rt > rtMax) = NaN;
        for j = 1:3
            perBlock = nan(numel(blockSets{j}),1);
            for b = 1:numel(blockSets{j})
                idx = find(blocks == blockSets{j}(b));
                idx = idx(1:min(nFirst,numel(idx)));
                perBlock(b) = mean(rt(idx),'omitnan');
            end
            S.(names{j})(i) = mean(perBlock,'omitnan');
        end
    end
end

function G = local_complete_cases(G)
    keep = isfinite(G.HP_S1) & isfinite(G.MP_S1) & isfinite(G.UP_S1) & ...
           isfinite(G.HP_S2) & isfinite(G.MP_S2) & isfinite(G.UP_S2);
    G = local_subset_group(G,find(keep));
end

function [G,msg] = local_match_S1S2_within_group(S1,S2,label)
    [ids,i1,i2] = intersect(S1.id,S2.id,'stable');
    G = struct('id',ids(:));
    names = {'HP','MP','UP'};
    for j = 1:3
        G.([names{j},'_S1']) = S1.(names{j})(i1);
        G.([names{j},'_S2']) = S2.(names{j})(i2);
    end
    msg = sprintf('%s: S1=%d, S2=%d, matched=%d; unmatched S1=%d, S2=%d.', ...
        label,numel(S1.id),numel(S2.id),numel(ids), ...
        numel(S1.id)-numel(ids),numel(S2.id)-numel(ids));
end

function G = local_subset_group(G,idx)
    names = fieldnames(G);
    for j = 1:numel(names), G.(names{j}) = G.(names{j})(idx); end
end

function [x,nb,nr,na] = local_rm3sd_inline(x)
    x = x(:); valid = isfinite(x); nb = sum(valid);
    remove = false(size(x));
    if nb >= 3
        m = mean(x(valid)); s = std(x(valid));
        if s > 0, remove = valid & abs(x-m) > 3*s; end
    end
    x(remove) = NaN; nr = sum(remove); na = sum(isfinite(x));
end

function T = local_desc_rows(group,control,hp,mp,up,meanSEM)
    values = {hp,mp,up}; labels = ["HP";"MP";"UP"];
    m = nan(3,1); sem = m;
    for j = 1:3
        summary = meanSEM(values{j}); m(j)=summary(1); sem(j)=summary(2);
    end
    T = table(repmat(string(group),3,1),repmat(string(control),3,1), ...
        labels,m,sem,'VariableNames', ...
        {'Group','Control','Predictability','MeanRT_ms','SEM_ms'});
end

function y = local_get_cell(H,P,group,control,pred)
    if group == "Group A", G = H;
    elseif group == "Group B", G = P;
    else, error('Unknown group: %s',group); end
    if control == "Controllable", suffix = '_S1';
    elseif control == "Uncontrollable", suffix = '_S2';
    else, error('Unknown condition: %s',control); end
    y = G.([char(pred),suffix]);
end
