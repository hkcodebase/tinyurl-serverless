package hk.prj;

import software.amazon.awssdk.http.apache.ApacheHttpClient;
import software.amazon.awssdk.regions.Region;
import software.amazon.awssdk.services.dynamodb.DynamoDbClient;

public class DependencyFactory {

    private DependencyFactory() {}

    public static DynamoDbClient dynamoDbClient() {
        return DynamoDbClient.builder()
                       .httpClientBuilder(ApacheHttpClient.builder())
                .region(Region.US_EAST_1)
                .build();
    }
}
