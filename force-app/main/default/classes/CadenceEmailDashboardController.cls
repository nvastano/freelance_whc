public with sharing class CadenceEmailDashboardController {

    private static final Integer MAX_CLICKED_CONTACTS = 200;

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

    public class RepMetrics implements Comparable {
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

        DashboardData data = new DashboardData();
        Map<Id, RepStat> repStatsByUser = new Map<Id, RepStat>();
        Map<Date, Integer> opensByDay = new Map<Date, Integer>();
        Set<Id> clickedEmailMessageIds = new Set<Id>();
        List<ClickedContact> listEmailClicked = new List<ClickedContact>();

        // ---- Manual path: EmailMessage (1:1 cadence-linked sends) ----
        for (AggregateResult ar : [
            SELECT CreatedById repId, IsOpened isOpened, IsLinkClicked isClicked,
                   IsBounced isBounced, HasReply hasReply, COUNT(Id) cnt
            FROM EmailMessage
            WHERE ActionCadenceStepTracker.ActionCadenceId = :cadenceId
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
            if (isOpened) {
                data.overview.opened += cnt;
            }
            if (isClicked) {
                data.overview.clicked += cnt;
            }
            if (hasReply) {
                data.overview.replied += cnt;
            }

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
            WHERE ActionCadenceStepTracker.ActionCadenceId = :cadenceId
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
            WHERE ActionCadenceStepTracker.ActionCadenceId = :cadenceId
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
            WHERE ActionCadenceStepTracker.ActionCadenceId = :cadenceId
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
            WHERE ActionCadenceStepTracker.ActionCadenceId = :cadenceId
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
            WHERE ActionCadenceStepTracker.ActionCadenceId = :cadenceId
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

        // ---- Assemble rates ----
        data.overview.openRate = rate(data.overview.opened, data.overview.sent);
        data.overview.clickRate = rate(data.overview.clicked, data.overview.sent);

        List<Id> repIds = new List<Id>(repStatsByUser.keySet());
        Map<Id, String> userNameById = new Map<Id, String>();
        for (User u : [SELECT Id, Name FROM User WHERE Id IN :repIds]) {
            userNameById.put(u.Id, u.Name);
        }
        for (RepStat rs : repStatsByUser.values()) {
            RepMetrics rm = new RepMetrics();
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

    private static Decimal rate(Integer numerator, Integer denominator) {
        if (denominator == null || denominator == 0) {
            return 0;
        }
        return (Decimal.valueOf(numerator) / Decimal.valueOf(denominator) * 100).setScale(1);
    }
}
