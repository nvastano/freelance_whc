public with sharing class IndustryAssignmentController {

    @AuraEnabled(cacheable=true)
    public static List<Industry_Assignment__c> getAssignments() {
        return [
            SELECT Id,
                   ZI_Primary_Industry__c,
                   ZI_Sub_Industry__c,
                   Assignment_Group__c,
                   Assignment_Group__r.Name,
                   LT_Member__c,
                   LT_Member__r.Name,
                   Active__c
            FROM Industry_Assignment__c
            ORDER BY ZI_Primary_Industry__c ASC, ZI_Sub_Industry__c ASC
        ];
    }

    @AuraEnabled(cacheable=true)
    public static List<Map<String, String>> getLTMembers() {
        List<Map<String, String>> members = new List<Map<String, String>>();
        Set<Id> seen = new Set<Id>();
        for (Industry_Assignment__c rec : [
            SELECT LT_Member__c, LT_Member__r.Name
            FROM Industry_Assignment__c
            WHERE LT_Member__c != null
            ORDER BY LT_Member__r.Name ASC
        ]) {
            if (!seen.contains(rec.LT_Member__c)) {
                seen.add(rec.LT_Member__c);
                members.add(new Map<String, String>{
                    'value' => rec.LT_Member__c,
                    'label' => rec.LT_Member__r.Name
                });
            }
        }
        return members;
    }

    @AuraEnabled(cacheable=true)
    public static List<Map<String, String>> getAssignmentGroups() {
        List<Map<String, String>> groups = new List<Map<String, String>>();
        Set<Id> seen = new Set<Id>();
        for (Industry_Assignment__c rec : [
            SELECT Assignment_Group__c, Assignment_Group__r.Name
            FROM Industry_Assignment__c
            WHERE Assignment_Group__c != null
            ORDER BY Assignment_Group__r.Name ASC
        ]) {
            if (!seen.contains(rec.Assignment_Group__c)) {
                seen.add(rec.Assignment_Group__c);
                groups.add(new Map<String, String>{
                    'value' => rec.Assignment_Group__c,
                    'label' => rec.Assignment_Group__r.Name
                });
            }
        }
        return groups;
    }

    @AuraEnabled
    public static Industry_Assignment__c saveAssignment(Industry_Assignment__c record) {
        if (!String.isBlank(record.ZI_Sub_Industry__c) && !String.isBlank(record.ZI_Primary_Industry__c)) {
            List<Industry_Assignment__c> dupes = [
                SELECT Id FROM Industry_Assignment__c
                WHERE ZI_Sub_Industry__c = :record.ZI_Sub_Industry__c
                AND ZI_Primary_Industry__c = :record.ZI_Primary_Industry__c
                AND Id != :record.Id
                LIMIT 1
            ];
            if (!dupes.isEmpty()) {
                throw new AuraHandledException(
                    '"' + record.ZI_Sub_Industry__c + '" is already assigned under "' + record.ZI_Primary_Industry__c + '". Each sub-industry can only have one assignment per primary industry.'
                );
            }
        }
        upsert record;
        return [
            SELECT Id,
                   ZI_Primary_Industry__c,
                   ZI_Sub_Industry__c,
                   Assignment_Group__c,
                   Assignment_Group__r.Name,
                   LT_Member__c,
                   LT_Member__r.Name,
                   Active__c
            FROM Industry_Assignment__c
            WHERE Id = :record.Id
        ];
    }

    @AuraEnabled(cacheable=true)
    public static List<String> getUsedSubIndustries() {
        Set<String> used = new Set<String>();
        for (Industry_Assignment__c rec : [
            SELECT ZI_Sub_Industry__c
            FROM Industry_Assignment__c
            WHERE ZI_Sub_Industry__c != null
        ]) {
            used.add(rec.ZI_Sub_Industry__c);
        }
        return new List<String>(used);
    }

    @AuraEnabled
    public static void deleteAssignment(Id recordId) {
        delete [SELECT Id FROM Industry_Assignment__c WHERE Id = :recordId];
    }

    @AuraEnabled
    public static void bulkSaveAssignments(List<Industry_Assignment__c> records) {
        update records;
    }

    @AuraEnabled(cacheable=true)
    public static List<PicklistOption> getPrimaryIndustryValues() {
        List<PicklistOption> options = new List<PicklistOption>();
        for (Schema.PicklistEntry e : Schema.SObjectType.Industry_Assignment__c
                .fields.ZI_Primary_Industry__c.getPicklistValues()) {
            if (e.isActive()) {
                options.add(new PicklistOption(e.getValue(), e.getLabel()));
            }
        }
        return options;
    }

    @AuraEnabled(cacheable=true)
    public static List<PicklistOption> getSubIndustryValues() {
        List<PicklistOption> options = new List<PicklistOption>();
        for (Schema.PicklistEntry e : Schema.SObjectType.Industry_Assignment__c
                .fields.ZI_Sub_Industry__c.getPicklistValues()) {
            if (e.isActive()) {
                options.add(new PicklistOption(e.getValue(), e.getLabel()));
            }
        }
        return options;
    }

    public class PicklistOption {
        @AuraEnabled public String value;
        @AuraEnabled public String label;
        public PicklistOption(String v, String l) { value = v; label = l; }
    }
}