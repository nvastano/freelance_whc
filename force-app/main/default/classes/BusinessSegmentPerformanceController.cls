public with sharing class BusinessSegmentPerformanceController {

    public class SegmentOption {
        @AuraEnabled public Id segmentId;
        @AuraEnabled public String business;
        @AuraEnabled public String cycle;
    }

    public class ChannelMetrics {
        @AuraEnabled public Integer emailSent = 0;
        @AuraEnabled public Integer emailOpened = 0;
        @AuraEnabled public Integer emailClicked = 0;
        @AuraEnabled public Integer emailReplied = 0;
        @AuraEnabled public Integer emailBounced = 0;
        @AuraEnabled public Decimal emailOpenRate = 0;
        @AuraEnabled public Decimal emailClickRate = 0;
        @AuraEnabled public Integer linkedInSent = 0;
        @AuraEnabled public Integer linkedInConnected = 0;
        @AuraEnabled public Decimal linkedInConnectRate = 0;
        @AuraEnabled public Integer callsMade = 0;
        @AuraEnabled public Integer callsConnected = 0;
        @AuraEnabled public Decimal callConnectRate = 0;
    }

    public class SegmentPerformance {
        @AuraEnabled public Id segmentId;
        @AuraEnabled public String business;
        @AuraEnabled public String cycle;
        @AuraEnabled public Integer accountCount = 0;
        @AuraEnabled public ChannelMetrics metrics = new ChannelMetrics();
    }

    public class TierOption {
        @AuraEnabled public String tierKey;
        @AuraEnabled public String label;
    }

    public class TierPerformance {
        @AuraEnabled public String tierKey;
        @AuraEnabled public String label;
        @AuraEnabled public Integer accountCount = 0;
        @AuraEnabled public ChannelMetrics metrics = new ChannelMetrics();
    }

    private class TierDefinition {
        String tierKey;
        String label;
        Decimal minValue;
        Decimal maxValue; // null = unbounded
        TierDefinition(String tierKey, String label, Decimal minValue, Decimal maxValue) {
            this.tierKey = tierKey;
            this.label = label;
            this.minValue = minValue;
            this.maxValue = maxValue;
        }
    }

    @AuraEnabled(cacheable=true)
    public static List<String> getCycleOptions() {
        List<String> values = new List<String>();
        for (Schema.PicklistEntry pe : Business_Segment__c.Cycle__c.getDescribe().getPicklistValues()) {
            if (pe.isActive()) {
                values.add(pe.getValue());
            }
        }
        return values;
    }

    @AuraEnabled(cacheable=true)
    public static List<SegmentOption> getBusinessSegmentOptions() {
        List<SegmentOption> options = new List<SegmentOption>();
        for (Business_Segment__c bs : [
            SELECT Id, Business__c, Cycle__c
            FROM Business_Segment__c
            ORDER BY Cycle__c, Business__c
            LIMIT 2000
        ]) {
            SegmentOption opt = new SegmentOption();
            opt.segmentId = bs.Id;
            opt.business = bs.Business__c;
            opt.cycle = bs.Cycle__c;
            options.add(opt);
        }
        return options;
    }

    @AuraEnabled(cacheable=true)
    public static SegmentPerformance getSegmentPerformance(Id segmentId, Date startDate, Date endDate) {
        if (segmentId == null) {
            return null;
        }
        List<SegmentPerformance> results = computePerformance(new Set<Id>{ segmentId }, startDate, endDate);
        return results.isEmpty() ? null : results[0];
    }

    @AuraEnabled(cacheable=true)
    public static List<SegmentPerformance> getCyclePerformance(String cycle, Date startDate, Date endDate) {
        if (String.isBlank(cycle) || startDate == null || endDate == null) {
            return new List<SegmentPerformance>();
        }
        Set<Id> segmentIds = new Set<Id>();
        for (Business_Segment__c bs : [
            SELECT Id FROM Business_Segment__c WHERE Cycle__c = :cycle LIMIT 2000
        ]) {
            segmentIds.add(bs.Id);
        }
        return computePerformance(segmentIds, startDate, endDate);
    }

    @AuraEnabled(cacheable=true)
    public static List<TierOption> getCompanySizeTiers(String tierType) {
        List<TierOption> options = new List<TierOption>();
        for (TierDefinition def : getTierDefinitions(tierType)) {
            TierOption opt = new TierOption();
            opt.tierKey = def.tierKey;
            opt.label = def.label;
            options.add(opt);
        }
        return options;
    }

    // Deliberately activity-first: resolving which of ~10K accounts (~37K contacts) fall in
    // each size tier before intersecting with outreach activity would risk the 50K SOQL-row
    // transaction limit on an org-wide, unscoped query. Starting from Task/EmailMessage
    // activity in the date range (a few hundred rows in a typical 30-day window) and only
    // then looking up size data for that small active set keeps every query bounded.
    // accountCount therefore reflects accounts with outreach activity in this window, not
    // every account that happens to fall in that size tier org-wide.
    @AuraEnabled(cacheable=true)
    public static List<TierPerformance> getCompanySizePerformance(String tierType, Date startDate, Date endDate) {
        if (startDate == null || endDate == null) {
            return new List<TierPerformance>();
        }
        List<TierDefinition> defs = getTierDefinitions(tierType);
        if (defs.isEmpty()) {
            return new List<TierPerformance>();
        }

        Map<Id, ChannelMetrics> metricsByAccountId = new Map<Id, ChannelMetrics>();

        for (AggregateResult ar : [
            SELECT AccountId accId, COUNT(Id) cnt
            FROM Task
            WHERE AccountId != null AND TaskSubtype = 'LinkedIn'
              AND ActivityDate >= :startDate AND ActivityDate <= :endDate
            GROUP BY AccountId
        ]) {
            getOrCreateMetrics(metricsByAccountId, (Id) ar.get('accId')).linkedInSent += (Integer) ar.get('cnt');
        }

        for (AggregateResult ar : [
            SELECT AccountId accId, COUNT(Id) cnt
            FROM Task
            WHERE AccountId != null
              AND LinkedIn_Connected_Date__c >= :startDate AND LinkedIn_Connected_Date__c <= :endDate
            GROUP BY AccountId
        ]) {
            getOrCreateMetrics(metricsByAccountId, (Id) ar.get('accId')).linkedInConnected += (Integer) ar.get('cnt');
        }

        for (AggregateResult ar : [
            SELECT AccountId accId, COUNT(Id) cnt
            FROM Task
            WHERE AccountId != null AND TaskSubtype = 'Call'
              AND ActivityDate >= :startDate AND ActivityDate <= :endDate
            GROUP BY AccountId
        ]) {
            getOrCreateMetrics(metricsByAccountId, (Id) ar.get('accId')).callsMade += (Integer) ar.get('cnt');
        }

        for (AggregateResult ar : [
            SELECT AccountId accId, COUNT(Id) cnt
            FROM Task
            WHERE AccountId != null AND CallDisposition = 'Connected'
              AND ActivityDate >= :startDate AND ActivityDate <= :endDate
            GROUP BY AccountId
        ]) {
            getOrCreateMetrics(metricsByAccountId, (Id) ar.get('accId')).callsConnected += (Integer) ar.get('cnt');
        }

        DateTime startDt = DateTime.newInstance(startDate, Time.newInstance(0, 0, 0, 0));
        DateTime endDt = DateTime.newInstance(endDate.addDays(1), Time.newInstance(0, 0, 0, 0));

        Set<Id> emailMessageIdsInRange = new Set<Id>();
        for (EmailMessage em : [
            SELECT Id FROM EmailMessage WHERE MessageDate >= :startDt AND MessageDate < :endDt
        ]) {
            emailMessageIdsInRange.add(em.Id);
        }

        if (!emailMessageIdsInRange.isEmpty()) {
            Map<Id, Id> contactIdByMessageId = new Map<Id, Id>();
            for (EmailMessageRelation rel : [
                SELECT EmailMessageId, RelationId
                FROM EmailMessageRelation
                WHERE EmailMessageId IN :emailMessageIdsInRange
                  AND RelationType = 'ToAddress' AND RelationObjectType = 'Contact'
            ]) {
                contactIdByMessageId.put(rel.EmailMessageId, rel.RelationId);
            }

            Set<Id> relatedContactIds = new Set<Id>(contactIdByMessageId.values());
            Map<Id, Id> accountIdByContactId = new Map<Id, Id>();
            if (!relatedContactIds.isEmpty()) {
                for (Contact c : [
                    SELECT Id, AccountId FROM Contact WHERE Id IN :relatedContactIds AND AccountId != null
                ]) {
                    accountIdByContactId.put(c.Id, c.AccountId);
                }
            }

            if (!contactIdByMessageId.isEmpty()) {
                for (EmailMessage em : [
                    SELECT Id, IsOpened, IsLinkClicked, HasReply, IsBounced
                    FROM EmailMessage
                    WHERE Id IN :contactIdByMessageId.keySet()
                ]) {
                    Id contactId = contactIdByMessageId.get(em.Id);
                    Id accountId = contactId != null ? accountIdByContactId.get(contactId) : null;
                    if (accountId == null) {
                        continue;
                    }
                    ChannelMetrics m = getOrCreateMetrics(metricsByAccountId, accountId);
                    m.emailSent++;
                    if (em.IsOpened) m.emailOpened++;
                    if (em.IsLinkClicked) m.emailClicked++;
                    if (em.HasReply) m.emailReplied++;
                    if (em.IsBounced) m.emailBounced++;
                }
            }
        }

        Map<String, TierPerformance> perfByTier = new Map<String, TierPerformance>();
        for (TierDefinition def : defs) {
            TierPerformance tp = new TierPerformance();
            tp.tierKey = def.tierKey;
            tp.label = def.label;
            perfByTier.put(def.tierKey, tp);
        }

        if (!metricsByAccountId.isEmpty()) {
            String fieldName = tierType == 'employees' ? 'NumberOfEmployees' : 'AnnualRevenue';
            Set<Id> activeAccountIds = metricsByAccountId.keySet();
            String query = 'SELECT Id, ' + fieldName + ' FROM Account WHERE Id IN :activeAccountIds AND ' +
                fieldName + ' != null';
            for (SObject rec : Database.query(query)) {
                Object rawValue = rec.get(fieldName);
                if (rawValue == null) {
                    continue;
                }
                Decimal value = Decimal.valueOf(String.valueOf(rawValue));
                String tierKey = resolveTierKey(value, defs);
                if (tierKey == null) {
                    continue;
                }
                TierPerformance tp = perfByTier.get(tierKey);
                tp.accountCount++;
                sumInto(tp.metrics, metricsByAccountId.get(rec.Id));
            }
        }

        List<TierPerformance> results = new List<TierPerformance>();
        for (TierDefinition def : defs) {
            TierPerformance tp = perfByTier.get(def.tierKey);
            finalizeRates(tp.metrics);
            results.add(tp);
        }
        return results;
    }

    private static List<TierDefinition> getTierDefinitions(String tierType) {
        if (tierType == 'employees') {
            return new List<TierDefinition>{
                new TierDefinition('emp_1_10', '1-10 Employees', 1, 11),
                new TierDefinition('emp_11_25', '11-25 Employees', 11, 26),
                new TierDefinition('emp_26_50', '26-50 Employees', 26, 51),
                new TierDefinition('emp_51_100', '51-100 Employees', 51, 101),
                new TierDefinition('emp_100_plus', '100+ Employees', 101, null)
            };
        }
        if (tierType == 'revenue') {
            return new List<TierDefinition>{
                new TierDefinition('rev_under_1m', 'Under $1M', 0, 1000000),
                new TierDefinition('rev_1_5m', '$1M - $5M', 1000000, 5000000),
                new TierDefinition('rev_5_10m', '$5M - $10M', 5000000, 10000000),
                new TierDefinition('rev_10_25m', '$10M - $25M', 10000000, 25000000),
                new TierDefinition('rev_25m_plus', '$25M+', 25000000, null)
            };
        }
        return new List<TierDefinition>();
    }

    private static String resolveTierKey(Decimal value, List<TierDefinition> defs) {
        for (TierDefinition def : defs) {
            Boolean aboveMin = def.minValue == null || value >= def.minValue;
            Boolean belowMax = def.maxValue == null || value < def.maxValue;
            if (aboveMin && belowMax) {
                return def.tierKey;
            }
        }
        return null;
    }

    private static ChannelMetrics getOrCreateMetrics(Map<Id, ChannelMetrics> metricsByAccountId, Id accountId) {
        ChannelMetrics m = metricsByAccountId.get(accountId);
        if (m == null) {
            m = new ChannelMetrics();
            metricsByAccountId.put(accountId, m);
        }
        return m;
    }

    private static void sumInto(ChannelMetrics target, ChannelMetrics source) {
        target.emailSent += source.emailSent;
        target.emailOpened += source.emailOpened;
        target.emailClicked += source.emailClicked;
        target.emailReplied += source.emailReplied;
        target.emailBounced += source.emailBounced;
        target.linkedInSent += source.linkedInSent;
        target.linkedInConnected += source.linkedInConnected;
        target.callsMade += source.callsMade;
        target.callsConnected += source.callsConnected;
    }

    private static void finalizeRates(ChannelMetrics m) {
        m.emailOpenRate = rate(m.emailOpened, m.emailSent);
        m.emailClickRate = rate(m.emailClicked, m.emailSent);
        m.linkedInConnectRate = rate(m.linkedInConnected, m.linkedInSent);
        m.callConnectRate = rate(m.callsConnected, m.callsMade);
    }

    private static List<SegmentPerformance> computePerformance(Set<Id> segmentIds, Date startDate, Date endDate) {
        if (segmentIds.isEmpty() || startDate == null || endDate == null) {
            return new List<SegmentPerformance>();
        }

        Map<Id, SegmentPerformance> perfBySegment = new Map<Id, SegmentPerformance>();
        for (Business_Segment__c bs : [
            SELECT Id, Business__c, Cycle__c FROM Business_Segment__c WHERE Id IN :segmentIds
        ]) {
            SegmentPerformance sp = new SegmentPerformance();
            sp.segmentId = bs.Id;
            sp.business = bs.Business__c;
            sp.cycle = bs.Cycle__c;
            perfBySegment.put(bs.Id, sp);
        }

        Map<Id, Id> accountIdToSegmentId = new Map<Id, Id>();
        for (Account acc : [
            SELECT Id, Business_Segment__c FROM Account WHERE Business_Segment__c IN :segmentIds
        ]) {
            accountIdToSegmentId.put(acc.Id, acc.Business_Segment__c);
            perfBySegment.get(acc.Business_Segment__c).accountCount++;
        }

        if (accountIdToSegmentId.isEmpty()) {
            return new List<SegmentPerformance>(perfBySegment.values());
        }

        // ---- LinkedIn + Calls: Task.AccountId is direct, single-hop, so these are plain aggregate queries ----
        for (AggregateResult ar : [
            SELECT AccountId accId, COUNT(Id) cnt
            FROM Task
            WHERE AccountId IN :accountIdToSegmentId.keySet()
              AND TaskSubtype = 'LinkedIn'
              AND ActivityDate >= :startDate AND ActivityDate <= :endDate
            GROUP BY AccountId
        ]) {
            SegmentPerformance sp = perfBySegment.get(accountIdToSegmentId.get((Id) ar.get('accId')));
            if (sp != null) {
                sp.metrics.linkedInSent += (Integer) ar.get('cnt');
            }
        }

        for (AggregateResult ar : [
            SELECT AccountId accId, COUNT(Id) cnt
            FROM Task
            WHERE AccountId IN :accountIdToSegmentId.keySet()
              AND LinkedIn_Connected_Date__c >= :startDate AND LinkedIn_Connected_Date__c <= :endDate
            GROUP BY AccountId
        ]) {
            SegmentPerformance sp = perfBySegment.get(accountIdToSegmentId.get((Id) ar.get('accId')));
            if (sp != null) {
                sp.metrics.linkedInConnected += (Integer) ar.get('cnt');
            }
        }

        for (AggregateResult ar : [
            SELECT AccountId accId, COUNT(Id) cnt
            FROM Task
            WHERE AccountId IN :accountIdToSegmentId.keySet()
              AND TaskSubtype = 'Call'
              AND ActivityDate >= :startDate AND ActivityDate <= :endDate
            GROUP BY AccountId
        ]) {
            SegmentPerformance sp = perfBySegment.get(accountIdToSegmentId.get((Id) ar.get('accId')));
            if (sp != null) {
                sp.metrics.callsMade += (Integer) ar.get('cnt');
            }
        }

        for (AggregateResult ar : [
            SELECT AccountId accId, COUNT(Id) cnt
            FROM Task
            WHERE AccountId IN :accountIdToSegmentId.keySet()
              AND CallDisposition = 'Connected'
              AND ActivityDate >= :startDate AND ActivityDate <= :endDate
            GROUP BY AccountId
        ]) {
            SegmentPerformance sp = perfBySegment.get(accountIdToSegmentId.get((Id) ar.get('accId')));
            if (sp != null) {
                sp.metrics.callsConnected += (Integer) ar.get('cnt');
            }
        }

        // ---- Email: no direct Account field, so resolve via EmailMessageRelation -> Contact ----
        Map<Id, Id> contactIdToAccountId = new Map<Id, Id>();
        for (Contact c : [
            SELECT Id, AccountId FROM Contact WHERE AccountId IN :accountIdToSegmentId.keySet()
        ]) {
            contactIdToAccountId.put(c.Id, c.AccountId);
        }

        if (!contactIdToAccountId.isEmpty()) {
            Map<Id, Id> emailMessageIdToContactId = new Map<Id, Id>();
            for (EmailMessageRelation rel : [
                SELECT EmailMessageId, RelationId
                FROM EmailMessageRelation
                WHERE RelationId IN :contactIdToAccountId.keySet()
                  AND RelationType = 'ToAddress' AND RelationObjectType = 'Contact'
            ]) {
                emailMessageIdToContactId.put(rel.EmailMessageId, rel.RelationId);
            }

            if (!emailMessageIdToContactId.isEmpty()) {
                DateTime startDt = DateTime.newInstance(startDate, Time.newInstance(0, 0, 0, 0));
                DateTime endDt = DateTime.newInstance(endDate.addDays(1), Time.newInstance(0, 0, 0, 0));
                for (EmailMessage em : [
                    SELECT Id, IsOpened, IsLinkClicked, HasReply, IsBounced
                    FROM EmailMessage
                    WHERE Id IN :emailMessageIdToContactId.keySet()
                      AND MessageDate >= :startDt AND MessageDate < :endDt
                ]) {
                    Id contactId = emailMessageIdToContactId.get(em.Id);
                    Id accountId = contactId != null ? contactIdToAccountId.get(contactId) : null;
                    Id segId = accountId != null ? accountIdToSegmentId.get(accountId) : null;
                    if (segId == null) {
                        continue;
                    }
                    ChannelMetrics m = perfBySegment.get(segId).metrics;
                    m.emailSent++;
                    if (em.IsOpened) m.emailOpened++;
                    if (em.IsLinkClicked) m.emailClicked++;
                    if (em.HasReply) m.emailReplied++;
                    if (em.IsBounced) m.emailBounced++;
                }
            }
        }

        for (SegmentPerformance sp : perfBySegment.values()) {
            finalizeRates(sp.metrics);
        }

        return new List<SegmentPerformance>(perfBySegment.values());
    }

    private static Decimal rate(Integer numerator, Integer denominator) {
        if (denominator == null || denominator == 0) {
            return 0;
        }
        return (Decimal.valueOf(numerator) / Decimal.valueOf(denominator) * 100).setScale(1);
    }
}
