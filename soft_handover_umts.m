%% =====================================================================
%  SIMULATION ET ANALYSE DU SOFT HANDOVER DANS UN RESEAU UMTS / WCDMA
%  Mini-projet MATLAB  (necessite MATLAB R2016b ou plus recent)

% Description : Ce script simule le déplacement d'un mobile entre deux
%  Node B, calcule les métriques radio (RSCP, Ec/No), applique
%  l'algorithme de soft handover (événements 1A, 1B, 1C), et analyse
%  les performances (Active Set, cellule servante, ping-pong).

%  ---------------------------------------------------------------------
%  Scenario : plusieurs Node B alignes le long d'une route. Un mobile
%  (UE) roule en ligne droite a vitesse constante et mesure le CPICH de
%  chaque cellule. L'algorithme de soft handover (evenements 3GPP
%  1A / 1B / 1C / 1D, avec hysteresis et Time-To-Trigger) met a jour
%  l'Active Set et choisit la cellule servante.
%
%  ENTREES  : distance entre Node B, position/vitesse du mobile,
%             puissance d'emission, modele de propagation, seuils,
%             hysteresis, TTT (+ shadowing, filtrage L3, charge...)
%  SORTIES  : RSCP, Ec/No, cellule servante, Active Set, zone de soft
%             handover, nombre de handovers, ping-pong.
%
%  Structure du fichier :
%    1. Parametres d'entree           (à modifier)
%    2. Simulation de reference       (run_simulation)
%    3. Resume chiffre
%    4. Graphiques demandes (4) + figure de synthese
%    5. Etude parametrique TTT x hysteresis (optionnelle)
%    6. Fonctions locales (modeles de propagation, algorithme, ...)
%% =====================================================================
clear; close all; clc;

%% ---------------------------------------------------------------------
%  1. PARAMETRES D'ENTREE
%  ---------------------------------------------------------------------
P = struct();

% --- 1.1 Topologie : Node B alignes sur l'axe x ------------------------
P.n_nodeB    = 3;                         % nombre de Node B
P.D_km       = 3.0;                       % distance entre Node B (km)
P.nodeB_x    = (0:P.n_nodeB-1)*P.D_km;    % abscisses des Node B (km)
P.nodeB_y    = zeros(1,P.n_nodeB);        % ordonnees des Node B (km)

% --- 1.2 Mobile ---------------------------------------------------------
P.x_start_km = 0;                         % position de depart (km)
P.x_end_km   = P.nodeB_x(end);            % position d'arrivee (km)
P.y_mobile_km= 0.10;                      % decalage lateral de la route (km)
P.v_kmh      = 50;                        % vitesse du mobile (km/h)
P.dt_s       = 0.2;                       % periode de mesure CPICH (s)

% --- 1.3 Emission / liaison radio --------------------------------------
P.f_MHz      = 2100;                      % frequence porteuse UMTS (MHz)
P.Ptx_dBm    = 43*ones(1,P.n_nodeB);      % puissance totale Node B (dBm) = 20 W
P.cpich_frac = 0.10;                      % CPICH = 10 % de la puissance (-10 dB)
P.load       = 0.70;                      % charge de la cellule (0..1)
P.Gant_dBi   = 15;                        % gain d'antenne Node B (dBi)
P.Lcable_dB  = 2;                         % pertes cables/connecteurs (dB)
P.Lmob_dB    = 0;                         % pertes cote mobile (corps...) (dB)
P.hb_m       = 30;                        % hauteur antenne Node B (m)
P.hm_m       = 1.5;                       % hauteur antenne mobile (m)
P.BW_Hz      = 3.84e6;                    % bande WCDMA (chip rate)
P.NF_dB      = 7;                         % facteur de bruit du mobile (dB)

% --- 1.4 Modele de propagation -----------------------------------------
%   'freespace'   : espace libre
%   'okumurahata' : Okumura-Hata (valide 150-1500 MHz, extrapole ici)
%   'cost231hata' : COST231-Hata (valide 1500-2000 MHz) <- recommande UMTS
%   'logdistance' : exposant n et PL a 100 m (modele pedagogique)
P.model      = 'cost231hata';
P.env        = 'suburban';                % 'urban' | 'suburban' | 'rural'
P.n_exp      = 3.5;                       % exposant (modele log-distance)

% --- 1.5 Evanouissements lents (shadowing log-normal) -------------------
P.sigma_dB   = 3;                         % ecart-type (dB) ; 0 = desactive
P.dcorr_m    = 50;                        % distance de decorrelation (m)

% --- 1.6 Algorithme de soft handover (3GPP TS 25.331) -------------------
P.HO_measure = 'EcNo';                    % grandeur de decision : 'EcNo' | 'RSCP'
P.L3_k       = 0;                         % filtrage couche 3 (0 = aucun, 4 = lent)
P.AS_Th_dB   = 4;                         % reporting range (fenetre) (dB)
P.Hyst_dB    = 2;                         % hysteresis (dB) : 1A/1B, 1C et 1D
P.TTT_s      = 0.32;                      % Time-To-Trigger (s)
P.AS_max     = 3;                         % taille max de l'Active Set
P.RSCP_min_dBm = -105;                    % seuil absolu : cellule detectable
P.EcNo_min_dB  = -18;                     % seuil absolu : cellule detectable
P.Tpp_s      = 5;                         % fenetre de detection du ping-pong (s)

% --- 1.7 Divers ---------------------------------------------------------
P.seed       = 1;                         % graine aleatoire (reproductibilite)
P.do_sweep   = true;                      % etude parametrique TTT x hysteresis ?
P.n_runs     = 10;                        % tirages de shadowing par point (sweep)

if strcmp(P.model,'okumurahata') && P.f_MHz > 1500
    warning('Okumura-Hata est valide jusqu''a 1500 MHz : resultats extrapoles a %d MHz.', P.f_MHz);
end

%% ---------------------------------------------------------------------
%  2. SIMULATION DE REFERENCE
%  ---------------------------------------------------------------------
R  = run_simulation(P, P.seed);
nB = P.n_nodeB;
col = lines(nB);

%% ---------------------------------------------------------------------
%  3. RESUME CHIFFRE
%  ---------------------------------------------------------------------
fprintf('\n================ RESULTATS (graine %d) ================\n', P.seed);
fprintf('Trajet                        : %.1f km a %d km/h (%.0f s)\n', ...
        P.x_end_km-P.x_start_km, P.v_kmh, R.T_tot);
fprintf('Modele / TTT / hysteresis     : %s / %.0f ms / %.1f dB\n', P.model, 1000*P.TTT_s, P.Hyst_dB);
fprintf('Handovers (cellule servante)  : %d\n', R.n_serv);
fprintf('Mises a jour Active Set       : %d  (1A: %d, 1B: %d, 1C: %d)\n', ...
        R.n_AS, R.n_1A, R.n_1B, R.n_1C);
fprintf('Ping-pong cellule servante    : %d\n', R.n_pp_serv);
fprintf('Ping-pong Active Set          : %d\n', R.n_pp_AS);
fprintf('Temps en soft handover        : %.1f %%\n', R.pct_SHO);
fprintf('Overhead soft handover        : %.1f %%  (taille moyenne AS - 1)\n', R.overhead);
fprintf('Temps Ec/No serv. < %.0f dB   : %.1f %%\n', P.EcNo_min_dB, 100*R.outage);
if isempty(R.zones)
    fprintf('Zone(s) de soft handover      : aucune\n');
else
    for z = 1:size(R.zones,1)
        fprintf('Zone de soft handover #%d      : x = %.2f -> %.2f km (largeur %.0f m)\n', ...
                z, R.zones(z,1), R.zones(z,2), 1000*(R.zones(z,2)-R.zones(z,1)));
    end
end

%% ---------------------------------------------------------------------
%  4. GRAPHIQUES
%  ---------------------------------------------------------------------
yl_names = arrayfun(@(i) sprintf('Node B %d',i), 1:nB, 'UniformOutput', false);

% ---- Figure 1 : RSCP = f(distance) --------------------------------------
figure('Name','RSCP = f(distance)','Color','w','Position',[80 80 900 700]);

subplot(2,1,1);                           % (a) loi theorique, un seul Node B
dd = logspace(log10(0.05), log10(6), 300);
models = {'freespace','okumurahata','cost231hata','logdistance'};
labs   = {'Espace libre','Okumura-Hata (extrapole)','COST231-Hata','Log-distance'};
for m = 1:numel(models)
    PLm = pathloss_dB(models{m}, dd, P);
    RSCPm = P.Ptx_dBm(1) + 10*log10(P.cpich_frac) + P.Gant_dBi ...
            - P.Lcable_dB - P.Lmob_dB - PLm;
    semilogx(dd, RSCPm, 'LineWidth', 1.6, 'DisplayName', labs{m}); hold on;
end
plot([0.05 6], P.RSCP_min_dBm*[1 1], 'k--', 'DisplayName', 'Seuil RSCP min');
grid on; xlabel('Distance au Node B (km)'); ylabel('RSCP (dBm)');
title('(a) RSCP selon le modele de propagation (sans shadowing)');
legend('Location','southwest');

subplot(2,1,2);                           % (b) le long du trajet simule
hold on;
yl = [P.RSCP_min_dBm-25, max(R.RSCP(:))+5];   % on coupe les cellules tres lointaines
shade_zones(R.zones, yl);
for i = 1:nB
    plot(R.x, R.RSCP(:,i), 'Color', col(i,:), 'LineWidth', 1.2, 'DisplayName', yl_names{i});
    plot(P.nodeB_x(i)*[1 1], yl, ':', 'Color', col(i,:), 'HandleVisibility','off');
end
plot([P.x_start_km P.x_end_km], P.RSCP_min_dBm*[1 1], 'k--', 'DisplayName','Seuil RSCP min');
ylim(yl); xlim([P.x_start_km P.x_end_km]); grid on;
xlabel('Position du mobile le long de la route (km)'); ylabel('RSCP (dBm)');
title('(b) RSCP recu de chaque Node B (zones bleutees = soft handover)');
legend('Location','southoutside','Orientation','horizontal');

% ---- Figure 2 : Ec/No = f(distance) -------------------------------------
figure('Name','Ec/No = f(distance)','Color','w','Position',[120 100 900 450]);
hold on;
yl = [-35, 0];                              % on coupe les cellules tres lointaines
shade_zones(R.zones, yl);
for i = 1:nB
    plot(R.x, R.EcNo(:,i), 'Color', col(i,:), 'LineWidth', 1.2, 'DisplayName', yl_names{i});
    plot(P.nodeB_x(i)*[1 1], yl, ':', 'Color', col(i,:), 'HandleVisibility','off');
end
plot([P.x_start_km P.x_end_km], P.EcNo_min_dB*[1 1], 'k--', 'DisplayName','Seuil Ec/No min');
ylim(yl); xlim([P.x_start_km P.x_end_km]); grid on;
xlabel('Position du mobile le long de la route (km)'); ylabel('Ec/No (dB)');
title('Ec/No du CPICH de chaque Node B (zones bleutees = soft handover)');
legend('Location','southoutside','Orientation','horizontal');

% ---- Figure 3 : evolution de la cellule servante ------------------------
figure('Name','Cellule servante','Color','w','Position',[160 120 900 400]);
h = stairs(R.t, R.serv, 'b', 'LineWidth', 1.8, 'DisplayName', 'Cellule servante'); hold on;
leg = h;
if ~isempty(R.sc)
    leg(end+1) = plot(R.sc(:,1), R.sc(:,3), 'ko', 'MarkerFaceColor','y', ...
                      'MarkerSize', 7, 'DisplayName', 'Handover');
end
if ~isempty(R.ppIdx)
    leg(end+1) = plot(R.sc(R.ppIdx,1), R.sc(R.ppIdx,3), 'rs', 'MarkerSize', 13, ...
                      'LineWidth', 2, 'DisplayName', 'Ping-pong');
end
set(gca,'YTick',1:nB,'YTickLabel',yl_names); ylim([0.5 nB+0.5]); grid on;
xlabel('Temps (s)   [position = x_{depart} + v \cdot t]'); ylabel('Cellule servante');
title(sprintf('Evolution de la cellule servante : %d handover(s), %d ping-pong', ...
              R.n_serv, R.n_pp_serv));
legend(leg, 'Location','southeast');

% ---- Figure 4 : evolution de l'Active Set -------------------------------
figure('Name','Active Set','Color','w','Position',[200 140 900 550]);
subplot(2,1,1);
imagesc(R.t, 1:nB, double(R.ASmask')); hold on;
colormap(gca, [1 1 1; 0.25 0.55 0.9]);
set(gca,'YDir','normal','YTick',1:nB,'YTickLabel',yl_names);
hs = stairs(R.t, R.serv, 'k', 'LineWidth', 1.2, 'DisplayName', 'Cellule servante');
leg = hs;
add_ev = R.ev(R.ev(:,3)>0, :);   rem_ev = R.ev(R.ev(:,4)>0, :);
if ~isempty(add_ev), leg(end+1) = plot(add_ev(:,1), add_ev(:,3), '^', 'MarkerFaceColor',[0 .7 0], ...
        'MarkerEdgeColor','k', 'MarkerSize',8, 'DisplayName','Ajout (1A / 1C)'); end
if ~isempty(rem_ev), leg(end+1) = plot(rem_ev(:,1), rem_ev(:,4), 'v', 'MarkerFaceColor',[.9 0 0], ...
        'MarkerEdgeColor','k', 'MarkerSize',8, 'DisplayName','Retrait (1B / 1C)'); end
xlabel('Temps (s)'); title('Active Set (bleu = cellule dans l''Active Set)');
legend(leg, 'Location','eastoutside');

subplot(2,1,2);
stairs(R.t, R.ASsize, 'LineWidth', 1.6); grid on;
ylim([0 P.AS_max+1]); set(gca,'YTick',0:P.AS_max+1);
xlabel('Temps (s)'); ylabel('Taille de l''Active Set');
title(sprintf('Taille de l''Active Set (%d MAJ, %.1f %% du temps en soft handover)', ...
              R.n_AS, R.pct_SHO));

%% ---------------------------------------------------------------------
%  5. ETUDE PARAMETRIQUE : TTT x HYSTERESIS
%     Chaque point = moyenne sur P.n_runs tirages de shadowing
%     (memes graines pour tous les points => comparaison equitable).
%  ---------------------------------------------------------------------
if P.do_sweep
    TTT_list  = [0 0.16 0.32 0.64 1.28];      % s
    Hyst_list = [0 0.5 1 2 3];                % dB  (doit rester < AS_Th_dB)
    nH = numel(Hyst_list); nTT = numel(TTT_list);
    M_hov = zeros(nH,nTT); M_ppS = M_hov; M_ppA = M_hov; M_ovh = M_hov;

    fprintf('\nEtude parametrique (%d x %d points, %d tirages)...\n', nH, nTT, P.n_runs);
    for ih = 1:nH
        for it = 1:nTT
            Pk = P; Pk.Hyst_dB = Hyst_list(ih); Pk.TTT_s = TTT_list(it);
            a = zeros(P.n_runs,4);
            for r = 1:P.n_runs
                Rk = run_simulation(Pk, 1000+r);
                a(r,:) = [Rk.n_serv, Rk.n_pp_serv, Rk.n_pp_AS, Rk.overhead];
            end
            m = mean(a,1);
            M_hov(ih,it) = m(1); M_ppS(ih,it) = m(2); M_ppA(ih,it) = m(3); M_ovh(ih,it) = m(4);
        end
    end

    figure('Name','Etude parametrique','Color','w','Position',[240 100 1000 750]);
    xt = arrayfun(@(v) sprintf('%g',1000*v), TTT_list,  'UniformOutput', false);
    yt = arrayfun(@(v) sprintf('%g',v),      Hyst_list, 'UniformOutput', false);
    subplot(2,2,1); plot_heat(M_hov, xt, yt, 'Handovers (cellule servante)', '%.1f');
    subplot(2,2,2); plot_heat(M_ppS, xt, yt, 'Ping-pong cellule servante',   '%.2f');
    subplot(2,2,3); plot_heat(M_ppA, xt, yt, 'Ping-pong Active Set',         '%.2f');
    subplot(2,2,4); plot_heat(M_ovh, xt, yt, 'Overhead soft handover (%)',   '%.1f');
    annotation('textbox', [0 0.955 1 0.04], 'EdgeColor', 'none', 'HorizontalAlignment', 'center', ...
               'FontWeight', 'bold', 'String', 'Effet du TTT et de l''hysteresis (moyenne sur plusieurs tirages)');
end

%% =====================================================================
%  6. FONCTIONS LOCALES
%  =====================================================================

function R = run_simulation(P, seed)
% RUN_SIMULATION  Execute un passage complet du mobile et renvoie les
% resultats dans la structure R.

    rng(seed);                                    % reproductibilite
    nB   = P.n_nodeB;
    v_ms = P.v_kmh/3.6;                           % vitesse en m/s

    % ---- Axe du temps et position du mobile ----------------------------
    R.T_tot = (P.x_end_km - P.x_start_km)*1000/v_ms;    % duree du trajet (s)
    t  = (0:P.dt_s:R.T_tot).';
    nT = numel(t);
    x  = P.x_start_km + v_ms*t/1000;              % position (km), nT x 1
    y  = P.y_mobile_km*ones(nT,1);

    % ---- Distances mobile <-> chaque Node B (nT x nB) -------------------
    d = sqrt((x - P.nodeB_x).^2 + (y - P.nodeB_y).^2);

    % ---- Affaiblissement de parcours -----------------------------------
    PL = pathloss_dB(P.model, d, P);

    % ---- Shadowing log-normal correle spatialement (Gudmundson) ---------
    %  S(k) = a*S(k-1) + sqrt(1-a^2)*sigma*w ,  a = exp(-dx/dcorr)
    %  -> processus AR(1) stationnaire d'ecart-type sigma, un par cellule.
    S = zeros(nT,nB);
    if P.sigma_dB > 0
        a = exp(-(v_ms*P.dt_s)/P.dcorr_m);
        S(1,:) = P.sigma_dB*randn(1,nB);
        for k = 2:nT
            S(k,:) = a*S(k-1,:) + sqrt(1-a^2)*P.sigma_dB*randn(1,nB);
        end
    end

    % ---- RSCP : puissance CPICH recue (dBm) ----------------------------
    %  RSCP = P_cpich + G_ant - L_cable - PL + shadowing - L_mobile
    Pcpich_dBm = P.Ptx_dBm + 10*log10(P.cpich_frac);          % 1 x nB
    RSCP = Pcpich_dBm + P.Gant_dBi - P.Lcable_dB - PL + S - P.Lmob_dB;

    % ---- Ec/No = Ec / Io -----------------------------------------------
    %  Ec = RSCP de la cellule consideree
    %  Io = puissance totale recue (toutes les cellules, a pleine charge
    %       'load') + bruit thermique.
    %  Puissance totale recue d'une cellule = RSCP * load / cpich_frac.
    N_mW   = 10^((-174 + 10*log10(P.BW_Hz) + P.NF_dB)/10);
    Prx_mW = 10.^(RSCP/10) * (P.load/P.cpich_frac);
    Io_mW  = sum(Prx_mW,2) + N_mW;                            % nT x 1
    EcNo   = RSCP - 10*log10(Io_mW);                          % dB

    % ---- Grandeur utilisee pour la decision + filtrage couche 3 ---------
    if strcmpi(P.HO_measure,'RSCP'), Qraw = RSCP; else, Qraw = EcNo; end
    Q = Qraw;
    if P.L3_k > 0
        alpha = 1/2^(P.L3_k/2);                   % F(n) = (1-a)F(n-1) + a*M(n)
        for k = 2:nT
            Q(k,:) = (1-alpha)*Q(k-1,:) + alpha*Qraw(k,:);
        end
    end

    % Cellule "detectable" (criteres absolus, equivalent critere S simplifie)
    det_all = (RSCP >= P.RSCP_min_dBm) & (EcNo >= P.EcNo_min_dB);

    % ---- Algorithme de soft handover ------------------------------------
    TTT = P.TTT_s;  H = P.Hyst_dB;  Rr = P.AS_Th_dB;  Nmax = P.AS_max;
    tol = 1e-9;

    inAS = false(1,nB);
    [~, b0] = max(Q(1,:));  inAS(b0) = true;      % Active Set initial
    serv = b0;                                    % cellule servante initiale
    t_add  = nan(1,nB);     % debut de la condition 1A pour chaque cellule
    t_drop = nan(1,nB);     % debut de la condition 1B
    t_rep  = nan(1,nB);     % debut de la condition 1C
    t_srv  = nan;  c_srv = 0;                     % condition 1D (cellule servante)
    ASmask  = false(nT,nB);
    servVec = zeros(nT,1);
    ev = zeros(0,4);        % evenements AS : [t type cell_ajoutee cell_retiree]
    sc = zeros(0,3);        % changements de servante : [t de vers]

    for k = 1:nT
        q = Q(k,:);  tk = t(k);  det = det_all(k,:);

        % ---- Evenement 1B : sortie de la reporting range (retrait) ------
        %  Condition : Q_i < Q_best - (R + H)  pendant TTT
        idx = find(inAS);
        qBest = max(q(idx));
        for i = idx
            if q(i) < qBest - (Rr + H)
                if isnan(t_drop(i)), t_drop(i) = tk; end
                if (tk - t_drop(i) >= TTT - tol) && nnz(inAS) > 1
                    inAS(i) = false;  t_drop(i) = nan;
                    ev(end+1,:) = [tk 2 0 i];                       %#ok<AGROW>
                end
            else
                t_drop(i) = nan;                  % condition rompue -> timer remis a 0
            end
        end

        % ---- Evenements 1A (ajout) et 1C (remplacement) -----------------
        idx = find(inAS);  nAS = numel(idx);
        qBest = max(q(idx));
        [qWorst, jw] = min(q(idx));  worst = idx(jw);
        readyA = false(1,nB);  readyC = false(1,nB);
        for i = find(~inAS)
            % 1A : Q_i > Q_best - (R - H) pendant TTT, cellule detectable
            if det(i) && q(i) > qBest - (Rr - H)
                if isnan(t_add(i)), t_add(i) = tk; end
                readyA(i) = (tk - t_add(i) >= TTT - tol);
            else
                t_add(i) = nan;
            end
            % 1C : AS plein et Q_i > Q_worst + H pendant TTT
            if nAS >= Nmax && det(i) && q(i) > qWorst + H
                if isnan(t_rep(i)), t_rep(i) = tk; end
                readyC(i) = (tk - t_rep(i) >= TTT - tol);
            else
                t_rep(i) = nan;
            end
        end
        if nAS < Nmax && any(readyA)
            qq = q;  qq(~readyA) = -inf;  [~, c] = max(qq);
            inAS(c) = true;  t_add(c) = nan;  t_rep(c) = nan;
            ev(end+1,:) = [tk 1 c 0];                               %#ok<AGROW>
        elseif nAS >= Nmax && any(readyC)
            qq = q;  qq(~readyC) = -inf;  [~, c] = max(qq);
            inAS(worst) = false;  inAS(c) = true;
            t_add(c) = nan;  t_rep(c) = nan;  t_drop(worst) = nan;
            ev(end+1,:) = [tk 3 c worst];                           %#ok<AGROW>
        end

        % ---- Evenement 1D : changement de cellule servante --------------
        %  Bascule vers la meilleure cellule de l'AS si
        %  Q_cand > Q_serv + H pendant TTT (evite le ping-pong).
        idx = find(inAS);
        if ~inAS(serv)                            % servante retiree de l'AS : bascule forcee
            [~, j] = max(q(idx));  newS = idx(j);
            sc(end+1,:) = [tk serv newS];                           %#ok<AGROW>
            serv = newS;  t_srv = nan;  c_srv = 0;
        else
            qo = q;  qo(~inAS) = -inf;  qo(serv) = -inf;
            [qc, c] = max(qo);
            if qc > q(serv) + H
                if isnan(t_srv) || c_srv ~= c, t_srv = tk;  c_srv = c; end
                if tk - t_srv >= TTT - tol
                    sc(end+1,:) = [tk serv c];                      %#ok<AGROW>
                    serv = c;  t_srv = nan;  c_srv = 0;
                end
            else
                t_srv = nan;  c_srv = 0;
            end
        end

        ASmask(k,:) = inAS;
        servVec(k)  = serv;
    end

    % ---- Post-traitement ------------------------------------------------
    ASsize = sum(ASmask,2);
    inSHO  = ASsize >= 2;                          % mobile en soft handover
    dif = diff([0; inSHO; 0]);
    zs  = find(dif == 1);  ze = find(dif == -1) - 1;
    zones = [x(zs), x(ze)];                        % zones de SHO (km)

    % Ping-pong de la cellule servante : A->B puis B->A en moins de Tpp
    n_pp_serv = 0;  ppIdx = [];
    for j = 1:size(sc,1)-1
        if sc(j+1,3) == sc(j,2) && (sc(j+1,1) - sc(j,1)) < P.Tpp_s
            n_pp_serv = n_pp_serv + 1;
            ppIdx(end+1) = j+1;                                     %#ok<AGROW>
        end
    end

    % Ping-pong de l'Active Set : une meme cellule ajoutee puis retiree
    % (ou l'inverse) en moins de Tpp
    acts = zeros(0,3);                             % [t cellule +1/-1]
    for j = 1:size(ev,1)
        if ev(j,3) > 0, acts(end+1,:) = [ev(j,1) ev(j,3) +1]; end   %#ok<AGROW>
        if ev(j,4) > 0, acts(end+1,:) = [ev(j,1) ev(j,4) -1]; end   %#ok<AGROW>
    end
    n_pp_AS = 0;
    for c = 1:nB
        a = acts(acts(:,2) == c, :);
        for j = 1:size(a,1)-1
            if a(j,3) ~= a(j+1,3) && (a(j+1,1) - a(j,1)) < P.Tpp_s
                n_pp_AS = n_pp_AS + 1;
            end
        end
    end

    % Temps pendant lequel la cellule servante est sous le seuil Ec/No
    lin = sub2ind([nT nB], (1:nT).', servVec);
    outage = mean(EcNo(lin) < P.EcNo_min_dB);

    % ---- Structure de sortie --------------------------------------------
    R.t = t;  R.x = x;  R.d = d;  R.RSCP = RSCP;  R.EcNo = EcNo;  R.Q = Q;
    R.ASmask = ASmask;  R.ASsize = ASsize;  R.serv = servVec;
    R.ev = ev;  R.sc = sc;  R.ppIdx = ppIdx;  R.zones = zones;
    R.n_1A = sum(ev(:,2)==1);  R.n_1B = sum(ev(:,2)==2);  R.n_1C = sum(ev(:,2)==3);
    R.n_AS = size(ev,1);       R.n_serv = size(sc,1);
    R.n_pp_serv = n_pp_serv;   R.n_pp_AS = n_pp_AS;
    R.pct_SHO  = 100*mean(inSHO);
    R.overhead = 100*(mean(ASsize) - 1);           % overhead SHO classique
    R.outage   = outage;
end

function PL = pathloss_dB(model, d_km, P)
% PATHLOSS_DB  Affaiblissement de parcours (dB), d_km peut etre une matrice.
    d  = max(d_km, 0.02);                          % evite log(0)
    f  = P.f_MHz;  hb = P.hb_m;  hm = P.hm_m;
    % correction hauteur mobile (ville petite/moyenne)
    a_hm = (1.1*log10(f) - 0.7)*hm - (1.56*log10(f) - 0.8);
    switch lower(model)
        case 'freespace'
            % FSPL = 32.45 + 20 log f(MHz) + 20 log d(km)
            PL = 32.45 + 20*log10(f) + 20*log10(d);
        case 'okumurahata'
            PL = 69.55 + 26.16*log10(f) - 13.82*log10(hb) - a_hm ...
                 + (44.9 - 6.55*log10(hb)).*log10(d);
            switch lower(P.env)
                case 'suburban', PL = PL - 2*(log10(f/28))^2 - 5.4;
                case 'rural',    PL = PL - 4.78*log10(f)^2 + 18.33*log10(f) - 40.94;
            end
        case 'cost231hata'
            Cm = 0;  if strcmpi(P.env,'urban'), Cm = 3; end   % 3 dB = grand centre urbain
            PL = 46.3 + 33.9*log10(f) - 13.82*log10(hb) - a_hm ...
                 + (44.9 - 6.55*log10(hb)).*log10(d) + Cm;
        case 'logdistance'
            d0 = 0.1;                              % distance de reference : 100 m
            PL0 = 32.45 + 20*log10(f) + 20*log10(d0);
            PL = PL0 + 10*P.n_exp*log10(d/d0);
        otherwise
            error('Modele de propagation inconnu : %s', model);
    end
end

function shade_zones(zones, yl)
% Colorie en bleu clair les zones de soft handover sur le graphique courant.
    for z = 1:size(zones,1)
        patch([zones(z,1) zones(z,2) zones(z,2) zones(z,1)], ...
              [yl(1) yl(1) yl(2) yl(2)], [0.3 0.6 1], ...
              'FaceAlpha', 0.18, 'EdgeColor', 'none', 'HandleVisibility', 'off');
    end
end

function plot_heat(M, xt, yt, ttl, fmt)
% Carte de chaleur avec valeurs ecrites dans les cases (lignes = hysteresis,
% colonnes = TTT).
    imagesc(M); colorbar; colormap(gca, parula);
    set(gca, 'XTick', 1:numel(xt), 'XTickLabel', xt, ...
             'YTick', 1:numel(yt), 'YTickLabel', yt, 'YDir', 'normal');
    xlabel('TTT (ms)'); ylabel('Hysteresis (dB)'); title(ttl);
    lo = min(M(:));  hi = max(M(:));  mid = (lo+hi)/2;
    for i = 1:size(M,1)
        for j = 1:size(M,2)
            tc = 'w';  if M(i,j) > mid, tc = 'k'; end
            text(j, i, sprintf(fmt, M(i,j)), 'HorizontalAlignment','center', 'Color', tc);
        end
    end
end
