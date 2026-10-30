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

        Account accA = new Account(
            Name = 'Test Account A', Business_Segment__c = segmentA.Id,
            NumberOfEmployees = 5, AnnualRevenue = 500000
        );
        // No outreach activity on this one - used to prove inactive accounts don't inflate
        // a size tier's accountCount even though it would otherwise fall in emp_1_10 too.
        Account accB = new Account(
            Name = 'Test Account B', Business_Segment__c = segmentB.Id,
            NumberOfEmployees = 8, AnnualRevenue = 400000
        );
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

    @isTest
    static void testGetCompanySizeTiersReturnsFiveEmployeeTiers() {
        Test.startTest();
        List<BusinessSegmentPerformanceController.TierOption> tiers =
            BusinessSegmentPerformanceController.getCompanySizeTiers('employees');
        Test.stopTest();

        System.assertEquals(5, tiers.size(), 'Expected 5 employee-count tiers');
        System.assertEquals('emp_1_10', tiers[0].tierKey, 'Expected tiers in ascending order');
        System.assertEquals('emp_100_plus', tiers[4].tierKey, 'Expected the last tier to be the open-ended one');
    }

    @isTest
    static void testGetCompanySizeTiersReturnsFiveRevenueTiers() {
        Test.startTest();
        List<BusinessSegmentPerformanceController.TierOption> tiers =
            BusinessSegmentPerformanceController.getCompanySizeTiers('revenue');
        Test.stopTest();

        System.assertEquals(5, tiers.size(), 'Expected 5 revenue tiers');
        System.assertEquals('rev_under_1m', tiers[0].tierKey, 'Expected tiers in ascending order');
        System.assertEquals('rev_25m_plus', tiers[4].tierKey, 'Expected the last tier to be the open-ended one');
    }

    @isTest
    static void testGetCompanySizeTiersWithUnknownTypeReturnsEmptyList() {
        Test.startTest();
        List<BusinessSegmentPerformanceController.TierOption> tiers =
            BusinessSegmentPerformanceController.getCompanySizeTiers('bogus');
        Test.stopTest();

        System.assertEquals(0, tiers.size(), 'Expected no tiers for an unrecognized tier type');
    }

    @isTest
    static void testGetCompanySizePerformanceByEmployeesRollsUpActiveAccountIntoCorrectTier() {
        Test.startTest();
        List<BusinessSegmentPerformanceController.TierPerformance> results =
            BusinessSegmentPerformanceController.getCompanySizePerformance(
                'employees', Date.today().addDays(-1), Date.today().addDays(1)
            );
        Test.stopTest();

        BusinessSegmentPerformanceController.TierPerformance emp1to10;
        for (BusinessSegmentPerformanceController.TierPerformance tp : results) {
            if (tp.tierKey == 'emp_1_10') {
                emp1to10 = tp;
            }
        }
        System.assertNotEquals(null, emp1to10, 'Expected the emp_1_10 tier to be present');
        // Only Account A has outreach activity, even though Account B (8 employees) also
        // falls in this tier - accountCount should reflect active accounts only.
        System.assertEquals(1, emp1to10.accountCount, 'Expected only the active account counted in this tier');
        System.assertEquals(2, emp1to10.metrics.linkedInSent, 'Expected 2 LinkedIn outreach touches');
        System.assertEquals(1, emp1to10.metrics.linkedInConnected, 'Expected 1 LinkedIn connection');
        System.assertEquals(2, emp1to10.metrics.callsMade, 'Expected 2 calls made');
        System.assertEquals(1, emp1to10.metrics.callsConnected, 'Expected 1 connected call');
        System.assertEquals(1, emp1to10.metrics.emailSent, 'Expected 1 tracked email resolved to this tier');
        System.assertEquals(50.0, emp1to10.metrics.linkedInConnectRate, 'Connect rate should be 1 of 2 = 50%');

        for (BusinessSegmentPerformanceController.TierPerformance tp : results) {
            if (tp.tierKey != 'emp_1_10') {
                System.assertEquals(0, tp.accountCount, 'Every other tier should have zero active accounts');
            }
        }
    }

    @isTest
    static void testGetCompanySizePerformanceByRevenueRollsUpActiveAccountIntoCorrectTier() {
        Test.startTest();
        List<BusinessSegmentPerformanceController.TierPerformance> results =
            BusinessSegmentPerformanceController.getCompanySizePerformance(
                'revenue', Date.today().addDays(-1), Date.today().addDays(1)
            );
        Test.stopTest();

        BusinessSegmentPerformanceController.TierPerformance underOneMillion;
        for (BusinessSegmentPerformanceController.TierPerformance tp : results) {
            if (tp.tierKey == 'rev_under_1m') {
                underOneMillion = tp;
            }
        }
        System.assertNotEquals(null, underOneMillion, 'Expected the rev_under_1m tier to be present');
        System.assertEquals(1, underOneMillion.accountCount, 'Expected only the active account counted in this tier');
        System.assertEquals(2, underOneMillion.metrics.linkedInSent, 'Expected 2 LinkedIn outreach touches');
    }

    @isTest
    static void testGetCompanySizePerformanceWithNullDatesReturnsEmptyList() {
        Test.startTest();
        List<BusinessSegmentPerformanceController.TierPerformance> results =
            BusinessSegmentPerformanceController.getCompanySizePerformance('employees', null, null);
        Test.stopTest();

        System.assertEquals(0, results.size(), 'Expected an empty list when dates are missing');
    }
}
