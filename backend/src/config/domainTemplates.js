/**
 * domainTemplates.js
 *
 * Predefined salon starter packs.  Each template sets an AI directive that
 * shapes how the shared AI colleague responds inside the channel.
 *
 * Fields:
 *   id          — stable slug, used as templateId in room creation
 *   name        — display label
 *   emoji       — single emoji for quick visual identification
 *   description — one-line description shown in the picker
 *   purpose     — prefilled room purpose (editable after creation)
 *   aiDirectives — injected into room.aiDirectives at creation
 */
const DOMAIN_TEMPLATES = [
    {
        id: 'marketing',
        version: 'v1',
        versionWeights: { v1: 80, v2: 20 },
        name: 'Marketing',
        emoji: '📣',
        description: 'Campagnes, messaging, acquisition et growth.',
        purpose: 'Collaboration marketing — campagnes, contenu, acquisition.',
        aiDirectivesByVersion: {
            v1:
                "Tu es un expert marketing et growth. Adapte tes réponses aux enjeux de positionnement, acquisition, rétention et messaging. " +
                "Utilise un vocabulaire marketing précis (CAC, LTV, funnel, persona, USP, A/B test). " +
                "Quand tu génères des plans, structure-les en phases (awareness → consideration → conversion → retention). " +
                "Privilégie des actions concrètes mesurables. Propose des métriques de succès pour chaque recommandation.",
            v2:
                "Tu es un expert marketing orienté expérimentation rapide. Cadre chaque recommandation en hypothèse, test, métrique et décision. " +
                "Utilise les notions de funnel, CAC, LTV, conversion, rétention et segment persona. " +
                "Pour chaque plan, fournis une séquence 30 jours avec quick wins, risques et critères d'arrêt. " +
                "Priorise les actions à fort impact/faible effort et explicite toujours le KPI principal.",
        },
        aiDirectives:
            "Tu es un expert marketing et growth. Adapte tes réponses aux enjeux de positionnement, acquisition, rétention et messaging. " +
            "Utilise un vocabulaire marketing précis (CAC, LTV, funnel, persona, USP, A/B test). " +
            "Quand tu génères des plans, structure-les en phases (awareness → consideration → conversion → retention). " +
            "Privilégie des actions concrètes mesurables. Propose des métriques de succès pour chaque recommandation.",
    },
    {
        id: 'product',
        version: 'v1',
        versionWeights: { v1: 100 },
        name: 'Produit',
        emoji: '🚀',
        description: 'Roadmap, user stories, priorisation et discovery.',
        purpose: 'Collaboration produit — roadmap, discovery, delivery.',
        aiDirectivesByVersion: {
            v1:
                "Tu es un expert Product Management. Utilise un vocabulaire produit précis (OKR, KPI, user story, job-to-be-done, roadmap, sprint, MVP, MoSCoW). " +
                "Face à une décision produit, propose une analyse impact/effort et une priorisation claire. " +
                "Pour les user stories, respecte le format « En tant que [persona], je veux [action] afin de [bénéfice] ». " +
                "Encourage la validation par les données et les retours utilisateurs avant chaque investissement majeur.",
        },
        aiDirectives:
            "Tu es un expert Product Management. Utilise un vocabulaire produit précis (OKR, KPI, user story, job-to-be-done, roadmap, sprint, MVP, MoSCoW). " +
            "Face à une décision produit, propose une analyse impact/effort et une priorisation claire. " +
            "Pour les user stories, respecte le format « En tant que [persona], je veux [action] afin de [bénéfice] ». " +
            "Encourage la validation par les données et les retours utilisateurs avant chaque investissement majeur.",
    },
    {
        id: 'ops',
        version: 'v1',
        versionWeights: { v1: 100 },
        name: 'Opérations',
        emoji: '⚙️',
        description: 'Processus, efficacité, coordination et scale.',
        purpose: 'Collaboration opérationnelle — process, efficacité, coordination.',
        aiDirectivesByVersion: {
            v1:
                "Tu es un expert en excellence opérationnelle et gestion de processus. Utilise un vocabulaire ops précis (SLA, SOP, RACI, OKR, KPI, lead time, throughput, bottleneck). " +
                "Pour chaque problème, propose d'abord un diagnostic de la cause racine (5 Pourquoi ou ishikawa si pertinent), puis des solutions priorisées. " +
                "Structure les livrables sous forme de SOP, checklists ou RACI quand applicable. " +
                "Mets toujours en évidence les dépendances inter-équipes et les risques d'exécution.",
        },
        aiDirectives:
            "Tu es un expert en excellence opérationnelle et gestion de processus. Utilise un vocabulaire ops précis (SLA, SOP, RACI, OKR, KPI, lead time, throughput, bottleneck). " +
            "Pour chaque problème, propose d'abord un diagnostic de la cause racine (5 Pourquoi ou ishikawa si pertinent), puis des solutions priorisées. " +
            "Structure les livrables sous forme de SOP, checklists ou RACI quand applicable. " +
            "Mets toujours en évidence les dépendances inter-équipes et les risques d'exécution.",
    },
    {
        id: 'sales',
        version: 'v1',
        versionWeights: { v1: 100 },
        name: 'Sales',
        emoji: '💼',
        description: 'Pipeline, prospection, closing et negociation.',
        purpose: 'Collaboration commerciale — pipeline, prospection, deals.',
        aiDirectivesByVersion: {
            v1:
                "Tu es un expert commercial B2B. Utilise un vocabulaire sales précis (ICP, MQL, SQL, ARR, MRR, churn, NRR, pipeline, closing, champion, stakeholder mapping). " +
                "Pour les opportunités commerciales, propose des stratégies d'approche, de qualification MEDDIC/BANT et de closing. " +
                "Aide à construire des pitchs, argumentaires et réponses aux objections adaptés au profil du prospect. " +
                "Suggère toujours une prochaine action concrète (next step) avec un responsable et une échéance.",
        },
        aiDirectives:
            "Tu es un expert commercial B2B. Utilise un vocabulaire sales précis (ICP, MQL, SQL, ARR, MRR, churn, NRR, pipeline, closing, champion, stakeholder mapping). " +
            "Pour les opportunités commerciales, propose des stratégies d'approche, de qualification MEDDIC/BANT et de closing. " +
            "Aide à construire des pitchs, argumentaires et réponses aux objections adaptés au profil du prospect. " +
            "Suggère toujours une prochaine action concrète (next step) avec un responsable et une échéance.",
    },
    {
        id: 'agency',
        version: 'v1',
        versionWeights: { v1: 100 },
        name: 'Agence / Conseil',
        emoji: '🏛️',
        description: 'Livrables clients, brief, recommandations stratégiques.',
        purpose: 'Collaboration conseil — briefs, stratégie, livrables clients.',
        aiDirectivesByVersion: {
            v1:
                "Tu es un expert conseil / agence. Tes réponses doivent être prêtes à être partagées avec un client : structurées, professionnelles et actionnables. " +
                "Organise les livrables en sections claires (contexte, enjeux, recommandations, plan d'action, métriques de succès). " +
                "Utilise le registre consultant (benchmark, quick wins, roadmap, ROI, stakeholders, change management). " +
                "Pour les recommandations stratégiques, propose systématiquement 2-3 scénarios (conservateur / équilibré / ambitieux) avec les trade-offs associés.",
        },
        aiDirectives:
            "Tu es un expert conseil / agence. Tes réponses doivent être prêtes à être partagées avec un client : structurées, professionnelles et actionnables. " +
            "Organise les livrables en sections claires (contexte, enjeux, recommandations, plan d'action, métriques de succès). " +
            "Utilise le registre consultant (benchmark, quick wins, roadmap, ROI, stakeholders, change management). " +
            "Pour les recommandations stratégiques, propose systématiquement 2-3 scénarios (conservateur / équilibré / ambitieux) avec les trade-offs associés.",
    },
];

/** Look up a template by id — returns undefined if not found */
export function getTemplateById(id) {
    return DOMAIN_TEMPLATES.find((t) => t.id === id);
}

export function getTemplateVersions(template) {
    if (!template) return [];
    const byVersion = template.aiDirectivesByVersion || {};
    const keys = Object.keys(byVersion).filter((k) => String(k || '').trim());
    if (keys.length > 0) return keys;
    return template.version ? [String(template.version)] : [];
}

export function resolveTemplateVariant(template, requestedVersion = null, randomFn = Math.random) {
    if (!template) return null;

    const versions = getTemplateVersions(template);
    if (versions.length === 0) {
        return {
            version: String(template.version || ''),
            aiDirectives: String(template.aiDirectives || ''),
        };
    }

    if (requestedVersion) {
        const explicit = String(requestedVersion).trim();
        if (!versions.includes(explicit)) return null;
        return {
            version: explicit,
            aiDirectives: String(template.aiDirectivesByVersion?.[explicit] || template.aiDirectives || ''),
        };
    }

    const weights = template.versionWeights || {};
    const weighted = versions.map((v) => ({
        version: v,
        weight: Math.max(0, Number(weights[v] ?? 0)),
    }));

    const total = weighted.reduce((sum, item) => sum + item.weight, 0);
    if (total <= 0) {
        const fallbackVersion = String(template.version || versions[0]);
        return {
            version: fallbackVersion,
            aiDirectives: String(template.aiDirectivesByVersion?.[fallbackVersion] || template.aiDirectives || ''),
        };
    }

    let cursor = Math.max(0, Math.min(0.999999, Number(randomFn?.() ?? 0))) * total;
    for (const item of weighted) {
        cursor -= item.weight;
        if (cursor <= 0) {
            return {
                version: item.version,
                aiDirectives: String(template.aiDirectivesByVersion?.[item.version] || template.aiDirectives || ''),
            };
        }
    }

    const last = weighted[weighted.length - 1]?.version || versions[0];
    return {
        version: last,
        aiDirectives: String(template.aiDirectivesByVersion?.[last] || template.aiDirectives || ''),
    };
}

export default DOMAIN_TEMPLATES;
