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
            sp.metrics.emailOpenRate = rate(sp.metrics.emailOpened, sp.metrics.emailSent);
            sp.metrics.emailClickRate = rate(sp.metrics.emailClicked, sp.metrics.emailSent);
            sp.metrics.linkedInConnectRate = rate(sp.metrics.linkedInConnected, sp.metrics.linkedInSent);
            sp.metrics.callConnectRate = rate(sp.metrics.callsConnected, sp.metrics.callsMade);
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
