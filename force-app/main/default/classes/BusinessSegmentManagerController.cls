public with sharing class BusinessSegmentManagerController {

    @AuraEnabled(cacheable=true)
    public static List<Business_Segment__c> getSegments() {
        return [
            SELECT Id, Name, Business__c, Cycle__c
            FROM Business_Segment__c
            ORDER BY Cycle__c ASC, Business__c ASC
        ];
    }

    @AuraEnabled(cacheable=true)
    public static List<PicklistOption> getCycleValues() {
        List<PicklistOption> options = new List<PicklistOption>();
        for (Schema.PicklistEntry e : Business_Segment__c.Cycle__c.getDescribe().getPicklistValues()) {
            if (e.isActive()) {
                options.add(new PicklistOption(e.getValue(), e.getLabel()));
            }
        }
        return options;
    }

    @AuraEnabled
    public static Business_Segment__c saveSegment(Business_Segment__c record) {
        if (!String.isBlank(record.Business__c) && !String.isBlank(record.Cycle__c)) {
            List<Business_Segment__c> dupes = [
                SELECT Id FROM Business_Segment__c
                WHERE Business__c = :record.Business__c
                AND Cycle__c = :record.Cycle__c
                AND Id != :record.Id
                LIMIT 1
            ];
            if (!dupes.isEmpty()) {
                String msg = '"' + record.Business__c + '" already exists for "' + record.Cycle__c + '". ' +
                    'Each business type can only have one record per cycle.';
                AuraHandledException ex = new AuraHandledException(msg);
                ex.setMessage(msg);
                throw ex;
            }
        }
        upsert record;
        return [SELECT Id, Name, Business__c, Cycle__c FROM Business_Segment__c WHERE Id = :record.Id];
    }

    @AuraEnabled
    public static void deleteSegment(Id recordId) {
        delete [SELECT Id FROM Business_Segment__c WHERE Id = :recordId];
    }

    public class PicklistOption {
        @AuraEnabled public String value;
        @AuraEnabled public String label;
        public PicklistOption(String v, String l) {
            value = v;
            label = l;
        }
    }
}
