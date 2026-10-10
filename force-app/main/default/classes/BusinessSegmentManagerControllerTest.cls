@isTest
private class BusinessSegmentManagerControllerTest {

    @testSetup
    static void setup() {
        insert new Business_Segment__c(Business__c = 'Test Segment A', Cycle__c = 'Cycle 1 - January');
        insert new Business_Segment__c(Business__c = 'Test Segment B', Cycle__c = 'Cycle 2 - February');
    }

    @isTest
    static void testGetSegmentsReturnsAllRecordsOrdered() {
        Test.startTest();
        List<Business_Segment__c> segments = BusinessSegmentManagerController.getSegments();
        Test.stopTest();

        System.assertEquals(2, segments.size(), 'Expected both test segments');
        System.assertEquals('Test Segment A', segments[0].Business__c, 'Expected Cycle 1 segment first');
    }

    @isTest
    static void testGetCycleValuesReturnsAllActivePicklistValues() {
        Test.startTest();
        List<BusinessSegmentManagerController.PicklistOption> options =
            BusinessSegmentManagerController.getCycleValues();
        Test.stopTest();

        System.assertEquals(8, options.size(), 'Expected all 8 Cycle picklist values');
    }

    @isTest
    static void testSaveSegmentCreatesNewRecord() {
        Test.startTest();
        Business_Segment__c saved = BusinessSegmentManagerController.saveSegment(
            new Business_Segment__c(Business__c = 'Brand New Segment', Cycle__c = 'Cycle 3 - March')
        );
        Test.stopTest();

        System.assertNotEquals(null, saved.Id, 'Expected the new record to be saved with an Id');
        System.assertEquals('Brand New Segment', saved.Business__c);
    }

    @isTest
    static void testSaveSegmentUpdatesExistingRecord() {
        Business_Segment__c existing = [
            SELECT Id FROM Business_Segment__c WHERE Business__c = 'Test Segment A' LIMIT 1
        ];

        Test.startTest();
        Business_Segment__c saved = BusinessSegmentManagerController.saveSegment(
            new Business_Segment__c(Id = existing.Id, Business__c = 'Test Segment A Updated', Cycle__c = 'Cycle 1 - January')
        );
        Test.stopTest();

        System.assertEquals(existing.Id, saved.Id, 'Expected the same record to be updated, not a new one');
        System.assertEquals('Test Segment A Updated', saved.Business__c);
    }

    @isTest
    static void testSaveSegmentRejectsDuplicateBusinessAndCycle() {
        Test.startTest();
        try {
            BusinessSegmentManagerController.saveSegment(
                new Business_Segment__c(Business__c = 'Test Segment A', Cycle__c = 'Cycle 1 - January')
            );
            System.assert(false, 'Expected an exception for a duplicate Business + Cycle combination');
        } catch (AuraHandledException e) {
            System.assert(e.getMessage().contains('Test Segment A'), 'Expected the error to name the duplicate business type');
        }
        Test.stopTest();
    }

    @isTest
    static void testDeleteSegmentRemovesRecord() {
        Business_Segment__c existing = [
            SELECT Id FROM Business_Segment__c WHERE Business__c = 'Test Segment B' LIMIT 1
        ];

        Test.startTest();
        BusinessSegmentManagerController.deleteSegment(existing.Id);
        Test.stopTest();

        List<Business_Segment__c> remaining = [
            SELECT Id FROM Business_Segment__c WHERE Id = :existing.Id
        ];
        System.assertEquals(0, remaining.size(), 'Expected the record to be deleted');
    }
}
