public without sharing class CadenceEmailDashboardController {

    private static final Integer MAX_CLICKED_CONTACTS = 200;
    private static final Integer MAX_DRILL_ROWS = 500;

    public class CadenceOption {
        @AuraEnabled public Id cadenceId;
        @AuraEnabled public String name;
        @AuraEnabled public String folderName;

        public CadenceOption(Id cadenceId, String name, String folderName) {
            this.cadenceId = cadenceId;
            this.name = name;
            this.folderName = String.isBlank(folderName) ? 'Uncategorized' : folderName;
        }
    }

    public class OverviewMetrics {
        @AuraEnabled public Integer sent = 0;
        @AuraEnabled public Integer delivered = 0;
        @AuraEnabled public Integer opened = 0;
        @AuraEnabled public Integer clicked = 0;
        @AuraEnabled public Integer bounced = 0;
        @AuraEnabled public Integer replied = 0;
        @AuraEnabled public Decimal openRate = 0;
        @AuraEnabled public Decimal clickRate = 0;
    }

    public class DayCount {
        @AuraEnabled public String day;
        @AuraEnabled public Integer count;
        public DayCount(Date d, Integer count) {
            this.day = String.valueOf(d);
            this.count = count;
        }
    }

    private class RepStat {
        Id repId;
        String repName;
        Integer sent = 0;
        Integer opened = 0;
        Integer clicked = 0;
        Integer replied = 0;
    }

    public class DrillDownRecord implements Comparable {
        @AuraEnabled public String contactName;
        @AuraEnabled public Id contactId;
        @AuraEnabled public String repName;
        @AuraEnabled public Datetime sentDate;
        @AuraEnabled public Boolean isOpened;
        @AuraEnabled public Datetime firstOpenedDate;
        @AuraEnabled public Boolean isClicked;
        @AuraEnabled public Datetime firstClickedDate;
        @AuraEnabled public Boolean isBounced;
        @AuraEnabled public Boolean hasReply;
        @AuraEnabled public String sourceType;

        public Integer compareTo(Object other) {
            DrillDownRecord o = (DrillDownRecord) other;
            if (this.sentDate == o.sentDate) return 0;
            if (o.sentDate == null) return -1;
            if (this.sentDate == null) return 1;
            return o.sentDate > this.sentDate ? 1 : -1;
        }
    }

    public class RepMetrics implements Comparable {
        @AuraEnabled public Id repId;
        @AuraEnabled public String repName;
        @AuraEnabled public Integer sent;
        @AuraEnabled public Integer opened;
        @AuraEnabled public Integer clicked;
        @AuraEnabled public Integer replied;
        @AuraEnabled public Decimal openRate;
        @AuraEnabled public Decimal clickRate;

        public Integer compareTo(Object other) {
            return ((RepMetrics) other).sent - this.sent;
        }
    }

    public class ClickedContact implements Comparable {
        @AuraEnabled public String contactName;
        @AuraEnabled public Datetime firstClickedDate;
        public ClickedContact(String contactName, Datetime firstClickedDate) {
            this.contactName = contactName;
            this.firstClickedDate = firstClickedDate;
        }

        public Integer compareTo(Object other) {
            Datetime otherDate = ((ClickedContact) other).firstClickedDate;
            if (this.firstClickedDate == otherDate) return 0;
            if (otherDate == null) return -1;
            if (this.firstClickedDate == null) return 1;
            return otherDate > this.firstClickedDate ? 1 : -1;
        }
    }

    public class DashboardData {
        @AuraEnabled public OverviewMetrics overview = new OverviewMetrics();
        @AuraEnabled public List<DayCount> opensOverTime = new List<DayCount>();
        @AuraEnabled public List<RepMetrics> byRep = new List<RepMetrics>();
        @AuraEnabled public List<ClickedContact> clickedContacts = new List<ClickedContact>();
    }

    // Resolves cadence → tracker IDs upfront so downstream queries never
    // use cross-object WHERE filters, which trigger a Salesforce SQL alias bug.
    private static Set<Id> getTrackerIds(Id cadenceId) {
        Set<Id> ids = new Set<Id>();
        for (ActionCadenceStepTracker t : [
            SELECT Id FROM ActionCadenceStepTracker
            WHERE ActionCadenceId = :cadenceId
            LIMIT 50000
        ]) {
            ids.add(t.Id);
        }
        return ids;
    }

    @AuraEnabled(cacheable=true)
    public static List<CadenceOption> getCadenceOptions() {
        List<CadenceOption> options = new List<CadenceOption>();
        for (ActionCadence ac : [
            SELECT Id, Name, FolderName
            FROM ActionCadence
            WHERE State = 'Active'
            ORDER BY FolderName, Name
            LIMIT 2000
        ]) {
            options.add(new CadenceOption(ac.Id, ac.Name, ac.FolderName));
        }
        return options;
    }

    @AuraEnabled(cacheable=true)
    public static DashboardData getDashboardData(Id cadenceId, Date startDate, Date endDate) {
        if (cadenceId == null || startDate == null || endDate == null) {
            return new DashboardData();
        }

        DateTime startDt = DateTime.newInstance(startDate, Time.newInstance(0, 0, 0, 0));
        DateTime endDt = DateTime.newInstance(endDate.addDays(1), Time.newInstance(0, 0, 0, 0));

        Set<Id> trackerIds = getTrackerIds(cadenceId);
        DashboardData data = new DashboardData();
        if (trackerIds.isEmpty()) return data;

        Map<Id, RepStat> repStatsByUser = new Map<Id, RepStat>();
        Map<Date, Integer> opensByDay = new Map<Date, Integer>();
        Set<Id> clickedEmailMessageIds = new Set<Id>();
        List<ClickedContact> listEmailClicked = new List<ClickedContact>();

        // ---- Manual path: EmailMessage ----
        for (AggregateResult ar : [
            SELECT CreatedById repId, IsOpened isOpened, IsLinkClicked isClicked,
                   IsBounced isBounced, HasReply hasReply, COUNT(Id) cnt
            FROM EmailMessage
            WHERE ActionCadenceStepTrackerId IN :trackerIds
              AND MessageDate >= :startDt AND MessageDate < :endDt
            GROUP BY CreatedById, IsOpened, IsLinkClicked, IsBounced, HasReply
        ]) {
            Integer cnt = (Integer) ar.get('cnt');
            Boolean isOpened = (Boolean) ar.get('isOpened');
            Boolean isClicked = (Boolean) ar.get('isClicked');
            Boolean isBounced = (Boolean) ar.get('isBounced');
            Boolean hasReply = (Boolean) ar.get('hasReply');
            Id repId = (Id) ar.get('repId');

            data.overview.sent += cnt;
            if (isBounced) {
                data.overview.bounced += cnt;
            } else {
                data.overview.delivered += cnt;
            }
            if (isOpened) data.overview.opened += cnt;
            if (isClicked) data.overview.clicked += cnt;
            if (hasReply) data.overview.replied += cnt;

            if (repId != null) {
                RepStat rs = repStatsByUser.get(repId);
                if (rs == null) {
                    rs = new RepStat();
                    rs.repId = repId;
                    repStatsByUser.put(repId, rs);
                }
                rs.sent += cnt;
                if (isOpened) rs.opened += cnt;
                if (isClicked) rs.clicked += cnt;
                if (hasReply) rs.replied += cnt;
            }
        }

        for (AggregateResult ar : [
            SELECT DAY_ONLY(FirstOpenedDate) day, COUNT(Id) cnt
            FROM EmailMessage
            WHERE ActionCadenceStepTrackerId IN :trackerIds
              AND IsOpened = true
              AND FirstOpenedDate >= :startDt AND FirstOpenedDate < :endDt
            GROUP BY DAY_ONLY(FirstOpenedDate)
        ]) {
            Date day = (Date) ar.get('day');
            Integer cnt = (Integer) ar.get('cnt');
            opensByDay.put(day, (opensByDay.containsKey(day) ? opensByDay.get(day) : 0) + cnt);
        }

        Map<Id, Datetime> clickDateByEmailMessageId = new Map<Id, Datetime>();
        for (EmailMessage em : [
            SELECT Id, FirstLinkClickedDate
            FROM EmailMessage
            WHERE ActionCadenceStepTrackerId IN :trackerIds
              AND IsLinkClicked = true
              AND MessageDate >= :startDt AND MessageDate < :endDt
            ORDER BY FirstLinkClickedDate DESC
            LIMIT :MAX_CLICKED_CONTACTS
        ]) {
            clickedEmailMessageIds.add(em.Id);
            clickDateByEmailMessageId.put(em.Id, em.FirstLinkClickedDate);
        }

        Map<Id, Id> contactIdByEmailMessageId = new Map<Id, Id>();
        for (EmailMessageRelation rel : [
            SELECT EmailMessageId, RelationId
            FROM EmailMessageRelation
            WHERE EmailMessageId IN :clickedEmailMessageIds
              AND RelationType = 'ToAddress' AND RelationObjectType = 'Contact'
        ]) {
            contactIdByEmailMessageId.put(rel.EmailMessageId, rel.RelationId);
        }

        Map<Id, String> contactNameById = new Map<Id, String>();
        Set<Id> contactIds = new Set<Id>(contactIdByEmailMessageId.values());
        for (Contact c : [SELECT Id, Name FROM Contact WHERE Id IN :contactIds]) {
            contactNameById.put(c.Id, c.Name);
        }

        List<ClickedContact> manualClicked = new List<ClickedContact>();
        for (Id emId : clickedEmailMessageIds) {
            Id contactId = contactIdByEmailMessageId.get(emId);
            String contactName = contactId != null ? contactNameById.get(contactId) : null;
            manualClicked.add(new ClickedContact(
                String.isBlank(contactName) ? 'Unknown Contact' : contactName,
                clickDateByEmailMessageId.get(emId)
            ));
        }

        // ---- Automated path: ListEmail / ListEmailSentResult ----
        for (AggregateResult ar : [
            SELECT ListEmail.OwnerId repId, IsOpened isOpened, IsClicked isClicked, HasReply hasReply, COUNT(Id) cnt
            FROM ListEmailSentResult
            WHERE ActionCadenceStepTrackerId IN :trackerIds
              AND CreatedDate >= :startDt AND CreatedDate < :endDt
              AND Result = 'Sent'
            GROUP BY ListEmail.OwnerId, IsOpened, IsClicked, HasReply
        ]) {
            Integer cnt = (Integer) ar.get('cnt');
            Boolean isOpened = (Boolean) ar.get('isOpened');
            Boolean isClicked = (Boolean) ar.get('isClicked');
            Boolean hasReply = (Boolean) ar.get('hasReply');
            Id repId = (Id) ar.get('repId');

            data.overview.sent += cnt;
            data.overview.delivered += cnt;
            if (isOpened) data.overview.opened += cnt;
            if (isClicked) data.overview.clicked += cnt;
            if (hasReply) data.overview.replied += cnt;

            if (repId != null) {
                RepStat rs = repStatsByUser.get(repId);
                if (rs == null) {
                    rs = new RepStat();
                    rs.repId = repId;
                    repStatsByUser.put(repId, rs);
                }
                rs.sent += cnt;
                if (isOpened) rs.opened += cnt;
                if (isClicked) rs.clicked += cnt;
                if (hasReply) rs.replied += cnt;
            }
        }

        for (AggregateResult ar : [
            SELECT DAY_ONLY(FirstOpenedDate) day, COUNT(Id) cnt
            FROM ListEmailSentResult
            WHERE ActionCadenceStepTrackerId IN :trackerIds
              AND IsOpened = true
              AND FirstOpenedDate >= :startDt AND FirstOpenedDate < :endDt
            GROUP BY DAY_ONLY(FirstOpenedDate)
        ]) {
            Date day = (Date) ar.get('day');
            Integer cnt = (Integer) ar.get('cnt');
            opensByDay.put(day, (opensByDay.containsKey(day) ? opensByDay.get(day) : 0) + cnt);
        }

        List<ListEmailSentResult> clickedResults = [
            SELECT Id, RecipientId, FirstClickedDate
            FROM ListEmailSentResult
            WHERE ActionCadenceStepTrackerId IN :trackerIds
              AND IsClicked = true
              AND CreatedDate >= :startDt AND CreatedDate < :endDt
            ORDER BY FirstClickedDate DESC
            LIMIT :MAX_CLICKED_CONTACTS
        ];
        Set<Id> recipientIds = new Set<Id>();
        for (ListEmailSentResult r : clickedResults) {
            if (r.RecipientId != null) recipientIds.add(r.RecipientId);
        }
        Map<Id, String> recipientNameById = new Map<Id, String>();
        for (Contact c : [SELECT Id, Name FROM Contact WHERE Id IN :recipientIds]) {
            recipientNameById.put(c.Id, c.Name);
        }
        for (Lead l : [SELECT Id, Name FROM Lead WHERE Id IN :recipientIds]) {
            recipientNameById.put(l.Id, l.Name);
        }
        for (ListEmailSentResult r : clickedResults) {
            String name = r.RecipientId != null ? recipientNameById.get(r.RecipientId) : null;
            listEmailClicked.add(new ClickedContact(
                String.isBlank(name) ? 'Unknown Contact' : name,
                r.FirstClickedDate
            ));
        }

        // ---- Assemble rates and rep metrics ----
        data.overview.openRate = rate(data.overview.opened, data.overview.sent);
        data.overview.clickRate = rate(data.overview.clicked, data.overview.sent);

        List<Id> repIds = new List<Id>(repStatsByUser.keySet());
        Map<Id, String> userNameById = new Map<Id, String>();
        for (User u : [SELECT Id, Name FROM User WHERE Id IN :repIds]) {
            userNameById.put(u.Id, u.Name);
        }
        for (RepStat rs : repStatsByUser.values()) {
            RepMetrics rm = new RepMetrics();
            rm.repId = rs.repId;
            rm.repName = userNameById.containsKey(rs.repId) ? userNameById.get(rs.repId) : 'Unknown';
            rm.sent = rs.sent;
            rm.opened = rs.opened;
            rm.clicked = rs.clicked;
            rm.replied = rs.replied;
            rm.openRate = rate(rs.opened, rs.sent);
            rm.clickRate = rate(rs.clicked, rs.sent);
            data.byRep.add(rm);
        }
        data.byRep.sort();

        List<Date> sortedDays = new List<Date>(opensByDay.keySet());
        sortedDays.sort();
        for (Date d : sortedDays) {
            data.opensOverTime.add(new DayCount(d, opensByDay.get(d)));
        }

        List<ClickedContact> allClicked = new List<ClickedContact>();
        allClicked.addAll(manualClicked);
        allClicked.addAll(listEmailClicked);
        allClicked.sort();
        for (Integer i = 0; i < allClicked.size() && i < MAX_CLICKED_CONTACTS; i++) {
            data.clickedContacts.add(allClicked[i]);
        }

        return data;
    }

    @AuraEnabled(cacheable=true)
    public static List<DrillDownRecord> getDrillDownRecords(
        Id cadenceId, Date startDate, Date endDate, String filterType, Id repId
    ) {
        if (cadenceId == null || startDate == null || endDate == null) {
            return new List<DrillDownRecord>();
        }
        DateTime startDt = DateTime.newInstance(startDate, Time.newInstance(0, 0, 0, 0));
        DateTime endDt = DateTime.newInstance(endDate.addDays(1), Time.newInstance(0, 0, 0, 0));

        Set<Id> trackerIds = getTrackerIds(cadenceId);
        if (trackerIds.isEmpty()) return new List<DrillDownRecord>();

        String emWhere = 'ActionCadenceStepTrackerId IN :trackerIds'
            + ' AND MessageDate >= :startDt AND MessageDate < :endDt';
        String leWhere = 'ActionCadenceStepTrackerId IN :trackerIds'
            + ' AND CreatedDate >= :startDt AND CreatedDate < :endDt AND Result = \'Sent\'';
        Boolean skipAutomated = false;

        // For the rep filter on ListEmailSentResult we resolve owner via ListEmail IDs
        // to avoid a cross-object WHERE filter (which causes a Salesforce SQL alias bug).
        Set<Id> repListEmailIds = new Set<Id>();

        if (filterType == 'opened') {
            emWhere += ' AND IsOpened = true';
            leWhere += ' AND IsOpened = true';
        } else if (filterType == 'clicked') {
            emWhere += ' AND IsLinkClicked = true';
            leWhere += ' AND IsClicked = true';
        } else if (filterType == 'bounced') {
            emWhere += ' AND IsBounced = true';
            skipAutomated = true;
        } else if (filterType == 'replied') {
            emWhere += ' AND HasReply = true';
            leWhere += ' AND HasReply = true';
        } else if (filterType == 'delivered') {
            emWhere += ' AND IsBounced = false';
        } else if (filterType == 'rep' && repId != null) {
            emWhere += ' AND CreatedById = :repId';
            for (ListEmail le : [SELECT Id FROM ListEmail WHERE OwnerId = :repId LIMIT 10000]) {
                repListEmailIds.add(le.Id);
            }
            if (repListEmailIds.isEmpty()) {
                skipAutomated = true;
            } else {
                leWhere += ' AND ListEmailId IN :repListEmailIds';
            }
        }

        List<EmailMessage> emails = Database.query(
            'SELECT Id, MessageDate, IsOpened, FirstOpenedDate, IsLinkClicked, '
            + 'FirstLinkClickedDate, IsBounced, HasReply, CreatedById '
            + 'FROM EmailMessage WHERE ' + emWhere
            + ' ORDER BY MessageDate DESC LIMIT 250'
        );

        List<ListEmailSentResult> listResults = new List<ListEmailSentResult>();
        if (!skipAutomated) {
            listResults = Database.query(
                'SELECT Id, RecipientId, CreatedDate, IsOpened, FirstOpenedDate, '
                + 'IsClicked, FirstClickedDate, HasReply, ListEmail.OwnerId '
                + 'FROM ListEmailSentResult WHERE ' + leWhere
                + ' ORDER BY CreatedDate DESC LIMIT 250'
            );
        }

        Set<Id> emailIds = new Set<Id>();
        Set<Id> repIds = new Set<Id>();
        Set<Id> recipientIds = new Set<Id>();

        for (EmailMessage em : emails) {
            emailIds.add(em.Id);
            if (em.CreatedById != null) repIds.add(em.CreatedById);
        }
        for (ListEmailSentResult r : listResults) {
            if (r.RecipientId != null) recipientIds.add(r.RecipientId);
            if (r.ListEmail != null && r.ListEmail.OwnerId != null) repIds.add(r.ListEmail.OwnerId);
        }

        Map<Id, Id> contactIdByEmailId = new Map<Id, Id>();
        if (!emailIds.isEmpty()) {
            for (EmailMessageRelation emr : [
                SELECT EmailMessageId, RelationId FROM EmailMessageRelation
                WHERE EmailMessageId IN :emailIds
                  AND RelationType = 'ToAddress' AND RelationObjectType = 'Contact'
            ]) {
                if (!contactIdByEmailId.containsKey(emr.EmailMessageId)) {
                    contactIdByEmailId.put(emr.EmailMessageId, emr.RelationId);
                }
            }
            recipientIds.addAll(contactIdByEmailId.values());
        }

        Map<Id, String> nameById = new Map<Id, String>();
        if (!recipientIds.isEmpty()) {
            for (Contact c : [SELECT Id, Name FROM Contact WHERE Id IN :recipientIds]) {
                nameById.put(c.Id, c.Name);
            }
            for (Lead l : [SELECT Id, Name FROM Lead WHERE Id IN :recipientIds]) {
                nameById.put(l.Id, l.Name);
            }
        }

        Map<Id, String> userNameById = new Map<Id, String>();
        if (!repIds.isEmpty()) {
            for (User u : [SELECT Id, Name FROM User WHERE Id IN :repIds]) {
                userNameById.put(u.Id, u.Name);
            }
        }

        List<DrillDownRecord> results = new List<DrillDownRecord>();

        for (EmailMessage em : emails) {
            DrillDownRecord rec = new DrillDownRecord();
            Id cId = contactIdByEmailId.get(em.Id);
            rec.contactId = cId;
            rec.contactName = (cId != null && nameById.containsKey(cId)) ? nameById.get(cId) : 'Unknown';
            rec.repName = (em.CreatedById != null && userNameById.containsKey(em.CreatedById))
                ? userNameById.get(em.CreatedById) : 'Unknown';
            rec.sentDate = em.MessageDate;
            rec.isOpened = em.IsOpened;
            rec.firstOpenedDate = em.FirstOpenedDate;
            rec.isClicked = em.IsLinkClicked;
            rec.firstClickedDate = em.FirstLinkClickedDate;
            rec.isBounced = em.IsBounced;
            rec.hasReply = em.HasReply;
            rec.sourceType = 'Manual';
            results.add(rec);
        }

        for (ListEmailSentResult r : listResults) {
            DrillDownRecord rec = new DrillDownRecord();
            rec.contactId = r.RecipientId;
            rec.contactName = (r.RecipientId != null && nameById.containsKey(r.RecipientId))
                ? nameById.get(r.RecipientId) : 'Unknown';
            Id ownerId = (r.ListEmail != null) ? r.ListEmail.OwnerId : null;
            rec.repName = (ownerId != null && userNameById.containsKey(ownerId))
                ? userNameById.get(ownerId) : 'Unknown';
            rec.sentDate = r.CreatedDate;
            rec.isOpened = r.IsOpened;
            rec.firstOpenedDate = r.FirstOpenedDate;
            rec.isClicked = r.IsClicked;
            rec.firstClickedDate = r.FirstClickedDate;
            rec.isBounced = false;
            rec.hasReply = r.HasReply;
            rec.sourceType = 'Automated';
            results.add(rec);
        }

        results.sort();
        if (results.size() > MAX_DRILL_ROWS) {
            List<DrillDownRecord> capped = new List<DrillDownRecord>();
            for (Integer i = 0; i < MAX_DRILL_ROWS; i++) {
                capped.add(results[i]);
            }
            return capped;
        }
        return results;
    }

    private static Decimal rate(Integer numerator, Integer denominator) {
        if (denominator == null || denominator == 0) {
            return 0;
        }
        return (Decimal.valueOf(numerator) / Decimal.valueOf(denominator) * 100).setScale(1);
    }
}
