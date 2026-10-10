@isTest
private class BusinessSegmentNameSyncTest {

    @isTest
    static void testNameIsSetFromBusinessOnInsert() {
        Business_Segment__c segment = new Business_Segment__c(
            Business__c = 'Short Business Name', Cycle__c = 'Cycle 1 - January'
        );

        Test.startTest();
        insert segment;
        Test.stopTest();

        Business_Segment__c inserted = [SELECT Name FROM Business_Segment__c WHERE Id = :segment.Id];
        System.assertEquals('Short Business Name', inserted.Name, 'Expected Name to mirror the short Business value exactly');
    }

    @isTest
    static void testNameIsTruncatedWithEllipsisWhenBusinessExceeds80Chars() {
        String longBusiness = 'This business description is deliberately written to be longer than eighty characters total';
        System.assert(longBusiness.length() > 80, 'Test setup assumption: the sample text must exceed 80 characters');

        Business_Segment__c segment = new Business_Segment__c(
            Business__c = longBusiness, Cycle__c = 'Cycle 1 - January'
        );

        Test.startTest();
        insert segment;
        Test.stopTest();

        Business_Segment__c inserted = [SELECT Name FROM Business_Segment__c WHERE Id = :segment.Id];
        System.assertEquals(80, inserted.Name.length(), 'Expected Name to be truncated to exactly 80 characters');
        System.assert(inserted.Name.endsWith('...'), 'Expected a truncation ellipsis at the end');
        System.assertEquals(longBusiness.left(77) + '...', inserted.Name, 'Expected the first 77 characters plus an ellipsis');
    }

    @isTest
    static void testNameIsResyncedOnUpdateWhenBusinessChanges() {
        Business_Segment__c segment = new Business_Segment__c(
            Business__c = 'Original Business Name', Cycle__c = 'Cycle 1 - January'
        );
        insert segment;

        Test.startTest();
        segment.Business__c = 'Updated Business Name';
        update segment;
        Test.stopTest();

        Business_Segment__c updated = [SELECT Name FROM Business_Segment__c WHERE Id = :segment.Id];
        System.assertEquals('Updated Business Name', updated.Name, 'Expected Name to follow the updated Business value');
    }
}
