@isTest
private class BusinessSegmentPerformanceControllerTest {

    @testSetup
    static void setup() {
        Business_Segment__c segmentA = new Business_Segment__c(
            Business__c = 'Test Segment A',
            Cycle__c = 'Cycle 1 - January'
        );
        Business_Segment__c segmentB = new Business_Segment__c(
            Business__c = 'Test Segment B',
            Cycle__c = 'Cycle 2 - February'
        );
        insert new List<Business_Segment__c>{ segmentA, segmentB };

        Account accA = new Account(Name = 'Test Account A', Business_Segment__c = segmentA.Id);
        Account accB = new Account(Name = 'Test Account B', Business_Segment__c = segmentB.Id);
        insert new List<Account>{ accA, accB };

        Contact conA = new Contact(FirstName = 'Test', LastName = 'Contact A', AccountId = accA.Id);
        insert conA;

        // Two LinkedIn outreach touches, one LinkedIn connection, one call connected, one call not connected.
        Task liSent1 = new Task(
            WhoId = conA.Id, TaskSubtype = 'LinkedIn', ActivityDate = Date.today(),
            Status = 'Completed', Subject = 'LinkedIn: Send Connection Request'
        );
        Task liSent2 = new Task(
            WhoId = conA.Id, TaskSubtype = 'LinkedIn', ActivityDate = Date.today(),
            Status = 'Completed', Subject = 'LinkedIn: Send Message'
        );
        Task liConnected = new Task(
            WhoId = conA.Id, LinkedIn_Connected_Date__c = Date.today(),
            Status = 'Completed', Subject = 'LinkedIn Connected'
        );
        Task callConnected = new Task(
            WhoId = conA.Id, TaskSubtype = 'Call', CallDisposition = 'Connected',
            ActivityDate = Date.today(), Status = 'Completed', Subject = 'Call'
        );
        Task callVoicemail = new Task(
            WhoId = conA.Id, TaskSubtype = 'Call', CallDisposition = 'Left Voicemail',
            ActivityDate = Date.today(), Status = 'Completed', Subject = 'Call'
        );
        insert new List<Task>{ liSent1, liSent2, liConnected, callConnected, callVoicemail };

        EmailMessage em = new EmailMessage(
            Subject = 'Test email', MessageDate = DateTime.now(), IsTracked = true, Incoming = false
        );
        insert em;
        EmailMessageRelation rel = new EmailMessageRelation(
            EmailMessageId = em.Id, RelationId = conA.Id,
            RelationType = 'ToAddress', RelationAddress = 'test@example.com'
        );
        insert rel;
    }

    @isTest
    static void testGetCycleOptionsReturnsAllActivePicklistValues() {
        Test.startTest();
        List<String> cycles = BusinessSegmentPerformanceController.getCycleOptions();
        Test.stopTest();

        System.assertEquals(8, cycles.size(), 'Expected all 8 Cycle picklist values');
        System.assert(cycles.contains('Cycle 1 - January'), 'Expected Cycle 1 - January in the list');
        System.assert(cycles.contains('Cycle 8 - October'), 'Expected Cycle 8 - October in the list');
    }

    @isTest
    static void testGetBusinessSegmentOptionsReturnsCreatedSegments() {
        Test.startTest();
        List<BusinessSegmentPerformanceController.SegmentOption> options =
            BusinessSegmentPerformanceController.getBusinessSegmentOptions();
        Test.stopTest();

        Set<String> businessNames = new Set<String>();
        for (BusinessSegmentPerformanceController.SegmentOption opt : options) {
            businessNames.add(opt.business);
        }
        System.assert(businessNames.contains('Test Segment A'), 'Expected Test Segment A in the options');
        System.assert(businessNames.contains('Test Segment B'), 'Expected Test Segment B in the options');
    }

    @isTest
    static void testGetSegmentPerformanceWithNullIdReturnsNull() {
        Test.startTest();
        BusinessSegmentPerformanceController.SegmentPerformance result =
            BusinessSegmentPerformanceController.getSegmentPerformance(null, Date.today(), Date.today());
        Test.stopTest();

        System.assertEquals(null, result, 'Expected null when no segment Id is provided');
    }

    @isTest
    static void testGetSegmentPerformanceRollsUpAllChannelsForLinkedSegment() {
        Business_Segment__c segmentA = [
            SELECT Id FROM Business_Segment__c WHERE Business__c = 'Test Segment A' LIMIT 1
        ];

        Test.startTest();
        BusinessSegmentPerformanceController.SegmentPerformance perf =
            BusinessSegmentPerformanceController.getSegmentPerformance(
                segmentA.Id, Date.today().addDays(-1), Date.today().addDays(1)
            );
        Test.stopTest();

        System.assertNotEquals(null, perf, 'Expected a performance result for a linked segment');
        System.assertEquals(1, perf.accountCount, 'Expected exactly one account linked to this segment');
        System.assertEquals(2, perf.metrics.linkedInSent, 'Expected 2 LinkedIn outreach touches');
        System.assertEquals(1, perf.metrics.linkedInConnected, 'Expected 1 LinkedIn connection');
        System.assertEquals(2, perf.metrics.callsMade, 'Expected 2 calls made');
        System.assertEquals(1, perf.metrics.callsConnected, 'Expected 1 connected call');
        System.assertEquals(1, perf.metrics.emailSent, 'Expected 1 tracked email resolved to this segment');
        System.assertEquals(50.0, perf.metrics.linkedInConnectRate, 'Connect rate should be 1 of 2 = 50%');
        System.assertEquals(50.0, perf.metrics.callConnectRate, 'Call connect rate should be 1 of 2 = 50%');
    }

    @isTest
    static void testGetCyclePerformanceReturnsOnlySegmentsInThatCycle() {
        Test.startTest();
        List<BusinessSegmentPerformanceController.SegmentPerformance> results =
            BusinessSegmentPerformanceController.getCyclePerformance(
                'Cycle 1 - January', Date.today().addDays(-1), Date.today().addDays(1)
            );
        Test.stopTest();

        System.assertEquals(1, results.size(), 'Expected only the one segment in Cycle 1 - January');
        System.assertEquals('Test Segment A', results[0].business, 'Expected Test Segment A');
    }

    @isTest
    static void testGetCyclePerformanceWithBlankCycleReturnsEmptyList() {
        Test.startTest();
        List<BusinessSegmentPerformanceController.SegmentPerformance> results =
            BusinessSegmentPerformanceController.getCyclePerformance(null, Date.today(), Date.today());
        Test.stopTest();

        System.assertEquals(0, results.size(), 'Expected an empty list for a blank cycle');
    }
}
