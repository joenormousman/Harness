public with sharing class HarnessReleaseHealth {
    public class Status {
        @AuraEnabled public Boolean ready;
        @AuraEnabled public String releaseChannel;
        @AuraEnabled public Datetime checkedAt;
    }

    @AuraEnabled(cacheable=true)
    public static Status check() {
        Status result = new Status();
        result.ready = true;
        result.releaseChannel = 'harness-governed';
        result.checkedAt = System.now();
        return result;
    }
}
