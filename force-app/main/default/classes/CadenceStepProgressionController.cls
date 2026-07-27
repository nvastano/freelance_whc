public without sharing class CadenceStepProgressionController {

    public class StepData {
        @AuraEnabled public String stepTitle;
        @AuraEnabled public String stepType;
        @AuraEnabled public String cadenceType;
        @AuraEnabled public Integer completedCount;
        @AuraEnabled public Integer activeCount;

        public StepData(String title, String type, String cadenceType, Integer completed, Integer active) {
            this.stepTitle      = title;
            this.stepType       = type;
            this.cadenceType    = cadenceType;
            this.completedCount = completed;
            this.activeCount    = active;
        }
    }

    public class RepOption {
        @AuraEnabled public String value;
        @AuraEnabled public String label;
        public RepOption(String v, String l) { this.value = v; this.label = l; }
    }

    @AuraEnabled(cacheable=true)
    public static List<StepData> getStepProgression(String dateRange, String userId) {
        String q = 'SELECT StepTitle, StepType, State, COUNT(Id) cnt ' +
                   'FROM ActionCadenceStepTracker ' +
                   'WHERE (StepTitle LIKE \'%#1%\' OR StepTitle LIKE \'%#2%\' OR StepTitle LIKE \'%#3%\' OR StepTitle LIKE \'%#4%\' OR StepTitle = \'Send InMail\') ' +
                   'AND StepType IN (\'AutoSendAnEmail\', \'SendAnEmail\', \'LinkedInMail\') ' +
                   'AND ActionCadenceTracker.ActionCadence.Name IN (' +
                       '\'LT - Manual Q226\',' +
                       '\'LT - Universal Auto Q226\',' +
                       '\'LT - Strategy Auto Q226\',' +
                       '\'LT - Creative Auto Q226\',' +
                       '\'LT - Growth Auto Q226\',' +
                       '\'LT - Product Auto Q226\',' +
                       '\'VA - Manual Q226\',' +
                       '\'VA - Universal Auto Q226\',' +
                       '\'VA - Strategy Auto Q226\',' +
                       '\'VA - Creative Auto Q226\',' +
                       '\'VA - Growth Auto Q226\',' +
                       '\'VA - Product Auto Q226\',' +
                       '\'VA - CM Manual\',' +
                       '\'VA - IM Manual\',' +
                       '\'CC - Manual Q226\'' +
                   ')';

        if (dateRange == 'this_month') {
            q += ' AND CreatedDate = THIS_MONTH';
        } else if (dateRange == 'this_week') {
            q += ' AND CreatedDate = THIS_WEEK';
        } else if (dateRange == 'last_week') {
            q += ' AND CreatedDate = LAST_WEEK';
        }

        if (String.isNotBlank(userId)) {
            q += ' AND ActionCadenceTracker.OwnerId = \'' + String.escapeSingleQuotes(userId) + '\'';
        }

        q += ' GROUP BY StepTitle, StepType, State ORDER BY StepTitle';

        Map<String, StepData> byKey = new Map<String, StepData>();
        for (AggregateResult ar : Database.query(q)) {
            String  title  = (String)  ar.get('StepTitle');
            String  type   = (String)  ar.get('StepType');
            String  state  = (String)  ar.get('State');
            Integer cnt    = ((Decimal) ar.get('cnt')).intValue();
            String  cType  = (type == 'AutoSendAnEmail') ? 'Auto' : 'Manual';
            String  key    = title + '|' + type;
            if (!byKey.containsKey(key)) byKey.put(key, new StepData(title, type, cType, 0, 0));
            StepData sd = byKey.get(key);
            if      (state == 'Completed') sd.completedCount += cnt;
            else if (state == 'Active')    sd.activeCount    += cnt;
        }
        return byKey.values();
    }

    @AuraEnabled(cacheable=true)
    public static List<RepOption> getReps() {
        Set<Id> ownerIds = new Set<Id>();
        for (AggregateResult ar : [
            SELECT ActionCadenceTracker.OwnerId ownerId
            FROM ActionCadenceStepTracker
            WHERE ActionCadenceTracker.OwnerId != null
            GROUP BY ActionCadenceTracker.OwnerId
        ]) {
            ownerIds.add((Id) ar.get('ownerId'));
        }
        List<RepOption> opts = new List<RepOption>();
        for (User u : [SELECT Id, Name FROM User WHERE Id IN :ownerIds ORDER BY Name]) {
            opts.add(new RepOption(u.Id, u.Name));
        }
        return opts;
    }
}