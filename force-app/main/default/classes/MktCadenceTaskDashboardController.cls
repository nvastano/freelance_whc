public with sharing class MktCadenceTaskDashboardController {

    private static final String MKT_FOLDER_NAME = 'MKT Cadence';
    private static final Integer NEW_INTENT_WINDOW_DAYS = 7;

    public class UserOption {
        @AuraEnabled public Id userId;
        @AuraEnabled public String name;
        public UserOption(Id userId, String name) {
            this.userId = userId;
            this.name = name;
        }
    }

    public class ActiveCadenceInfo {
        @AuraEnabled public String contactName;
        @AuraEnabled public Id contactId;
        @AuraEnabled public String cadenceName;
        @AuraEnabled public String ownerName;
        @AuraEnabled public Datetime enrolledDate;
    }

    public class FollowUpTaskInfo {
        @AuraEnabled public Id taskId;
        @AuraEnabled public String contactName;
        @AuraEnabled public Id contactId;
        @AuraEnabled public String subject;
        @AuraEnabled public Date dueDate;
        @AuraEnabled public String ownerName;
    }

    public class NewIntentInfo {
        @AuraEnabled public String topic;
        @AuraEnabled public String category;
        @AuraEnabled public Decimal surgeScore;
        @AuraEnabled public Date signalDate;
        @AuraEnabled public String suggestedCadenceName;
    }

    public class AccountRow {
        @AuraEnabled public Id accountId;
        @AuraEnabled public String accountName;
        @AuraEnabled public List<ActiveCadenceInfo> activeCadences = new List<ActiveCadenceInfo>();
        @AuraEnabled public List<FollowUpTaskInfo> followUpTasks = new List<FollowUpTaskInfo>();
        @AuraEnabled public List<NewIntentInfo> newIntentSignals = new List<NewIntentInfo>();
    }

    @AuraEnabled(cacheable=true)
    public static List<UserOption> getUserOptions() {
        Set<Id> ownerIds = new Set<Id>();

        Set<Id> mktCadenceIds = getMktCadenceIds();
        if (!mktCadenceIds.isEmpty()) {
            for (ActionCadenceTracker t : [
                SELECT OwnerId
                FROM ActionCadenceTracker
                WHERE ActionCadenceId IN :mktCadenceIds AND State = 'Active'
            ]) {
                ownerIds.add(t.OwnerId);
            }
        }

        for (Task t : [
            SELECT OwnerId
            FROM Task
            WHERE TaskSubtype = 'Task' AND Status != 'Completed' AND Subject LIKE '%MKT%'
        ]) {
            ownerIds.add(t.OwnerId);
        }

        List<UserOption> options = new List<UserOption>();
        if (!ownerIds.isEmpty()) {
            for (User u : [SELECT Id, Name FROM User WHERE Id IN :ownerIds ORDER BY Name]) {
                options.add(new UserOption(u.Id, u.Name));
            }
        }
        return options;
    }

    @AuraEnabled(cacheable=true)
    public static List<AccountRow> getDashboardData(Id ownerId) {
        Set<Id> mktCadenceIds = getMktCadenceIds();
        Map<Id, String> cadenceNamesById = new Map<Id, String>();
        if (!mktCadenceIds.isEmpty()) {
            for (ActionCadence ac : [SELECT Id, Name FROM ActionCadence WHERE Id IN :mktCadenceIds]) {
                cadenceNamesById.put(ac.Id, ac.Name);
            }
        }

        Map<Id, AccountRow> rowsByAccountId = new Map<Id, AccountRow>();
        Map<Id, Id> contactToAccountId = new Map<Id, Id>();
        Set<Id> contactIdsToResolve = new Set<Id>();

        List<ActionCadenceTracker> trackers = new List<ActionCadenceTracker>();
        if (!mktCadenceIds.isEmpty()) {
            String trackerQuery = 'SELECT TargetId, OwnerId, Owner.Name, ActionCadenceId, CreatedDate ' +
                'FROM ActionCadenceTracker WHERE ActionCadenceId IN :mktCadenceIds AND State = \'Active\' ' +
                'AND TargetId IN (SELECT Id FROM Contact)';
            if (ownerId != null) {
                trackerQuery += ' AND OwnerId = :ownerId';
            }
            trackers = Database.query(trackerQuery);
        }
        for (ActionCadenceTracker t : trackers) {
            contactIdsToResolve.add(t.TargetId);
        }

        String taskQuery = 'SELECT Id, WhoId, Who.Name, Subject, ActivityDate, OwnerId, Owner.Name ' +
            'FROM Task WHERE TaskSubtype = \'Task\' AND Status != \'Completed\' AND Subject LIKE \'%MKT%\' ' +
            'AND WhoId IN (SELECT Id FROM Contact)';
        if (ownerId != null) {
            taskQuery += ' AND OwnerId = :ownerId';
        }
        List<Task> followUpTasks = Database.query(taskQuery);
        for (Task t : followUpTasks) {
            contactIdsToResolve.add(t.WhoId);
        }

        if (!contactIdsToResolve.isEmpty()) {
            for (Contact c : [
                SELECT Id, AccountId, Account.Name
                FROM Contact
                WHERE Id IN :contactIdsToResolve AND AccountId != null
            ]) {
                contactToAccountId.put(c.Id, c.AccountId);
                if (!rowsByAccountId.containsKey(c.AccountId)) {
                    AccountRow row = new AccountRow();
                    row.accountId = c.AccountId;
                    row.accountName = c.Account.Name;
                    rowsByAccountId.put(c.AccountId, row);
                }
            }
        }

        for (ActionCadenceTracker t : trackers) {
            Id acctId = contactToAccountId.get(t.TargetId);
            if (acctId == null || !rowsByAccountId.containsKey(acctId)) {
                continue;
            }
            ActiveCadenceInfo info = new ActiveCadenceInfo();
            info.contactId = t.TargetId;
            info.cadenceName = cadenceNamesById.get(t.ActionCadenceId);
            info.ownerName = t.Owner != null ? t.Owner.Name : null;
            info.enrolledDate = t.CreatedDate;
            rowsByAccountId.get(acctId).activeCadences.add(info);
        }

        for (Task t : followUpTasks) {
            Id acctId = contactToAccountId.get(t.WhoId);
            if (acctId == null || !rowsByAccountId.containsKey(acctId)) {
                continue;
            }
            FollowUpTaskInfo info = new FollowUpTaskInfo();
            info.taskId = t.Id;
            info.contactId = t.WhoId;
            info.contactName = t.Who != null ? t.Who.Name : null;
            info.subject = t.Subject;
            info.dueDate = t.ActivityDate;
            info.ownerName = t.Owner != null ? t.Owner.Name : null;
            rowsByAccountId.get(acctId).followUpTasks.add(info);
        }

        if (!contactIdsToResolve.isEmpty()) {
            Map<Id, String> contactNames = new Map<Id, String>();
            for (Contact c : [SELECT Id, Name FROM Contact WHERE Id IN :contactIdsToResolve]) {
                contactNames.put(c.Id, c.Name);
            }
            for (AccountRow row : rowsByAccountId.values()) {
                for (ActiveCadenceInfo info : row.activeCadences) {
                    info.contactName = contactNames.get(info.contactId);
                }
            }
        }

        if (!rowsByAccountId.isEmpty()) {
            Date sinceDate = Date.today().addDays(-NEW_INTENT_WINDOW_DAYS);
            for (DOZISF__ZoomInfo_Intent__c intent : [
                SELECT DOZISF__Account__c, DOZISF__Topic__c, DOZISF__Categories__c,
                       DOZISF__Surge_Score__c, DOZISF__Signal_Date__c
                FROM DOZISF__ZoomInfo_Intent__c
                WHERE DOZISF__Account__c IN :rowsByAccountId.keySet()
                      AND DOZISF__Signal_Date__c >= :sinceDate
            ]) {
                NewIntentInfo info = new NewIntentInfo();
                info.topic = intent.DOZISF__Topic__c;
                info.category = intent.DOZISF__Categories__c;
                info.surgeScore = intent.DOZISF__Surge_Score__c;
                info.signalDate = intent.DOZISF__Signal_Date__c;
                info.suggestedCadenceName = findMatchingCadenceName(intent.DOZISF__Topic__c, cadenceNamesById.values());
                rowsByAccountId.get(intent.DOZISF__Account__c).newIntentSignals.add(info);
            }
        }

        List<AccountRow> results = rowsByAccountId.values();
        results.sort(new AccountRowComparator());
        return results;
    }

    private static Set<Id> getMktCadenceIds() {
        Set<Id> folderIds = new Set<Id>();
        for (Folder f : [SELECT Id FROM Folder WHERE Name = :MKT_FOLDER_NAME]) {
            folderIds.add(f.Id);
        }
        Set<Id> cadenceIds = new Set<Id>();
        if (!folderIds.isEmpty()) {
            for (ActionCadence ac : [SELECT Id FROM ActionCadence WHERE FolderId IN :folderIds]) {
                cadenceIds.add(ac.Id);
            }
        }
        return cadenceIds;
    }

    private static String findMatchingCadenceName(String topic, List<String> cadenceNames) {
        if (String.isBlank(topic)) {
            return null;
        }
        String needle = 'MKT - ' + topic;
        for (String name : cadenceNames) {
            if (name.equalsIgnoreCase(needle)) {
                return name;
            }
        }
        return null;
    }

    private class AccountRowComparator implements Comparator<AccountRow> {
        public Integer compare(AccountRow a, AccountRow b) {
            Integer aCount = a.newIntentSignals.size() > 0 ? 1 : 0;
            Integer bCount = b.newIntentSignals.size() > 0 ? 1 : 0;
            if (aCount != bCount) {
                return bCount - aCount;
            }
            return a.accountName.compareTo(b.accountName);
        }
    }
}
