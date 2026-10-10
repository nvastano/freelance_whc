trigger BusinessSegmentNameSync on Business_Segment__c (before insert, before update) {
    for (Business_Segment__c segment : Trigger.new) {
        if (String.isBlank(segment.Business__c)) {
            continue;
        }
        segment.Name = segment.Business__c.length() > 80
            ? segment.Business__c.left(77) + '...'
            : segment.Business__c;
    }
}
