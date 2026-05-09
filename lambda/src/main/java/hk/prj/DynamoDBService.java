package hk.prj;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import software.amazon.awssdk.services.dynamodb.DynamoDbClient;
import software.amazon.awssdk.services.dynamodb.model.*;

import java.util.HashMap;
import java.util.Map;

public class DynamoDBService {

    private static final DynamoDbClient DYNAMODB_CLIENT = DependencyFactory.dynamoDbClient();
    private static final Logger LOGGER = LoggerFactory.getLogger(DynamoDBService.class);
    private static final String TABLE_NAME = "Url";
    private static final String keyExpression = "#hash = :hash";
    private static final String pk = "hash";

    public static String getRedirectUrl(String pkValue) {
        Map<String,String> expressionAttributesNames = new HashMap<>();
        expressionAttributesNames.put("#"+pk,pk);

        Map<String,AttributeValue> expressionAttributeValues = new HashMap<>();
        expressionAttributeValues.put(":"+pk, AttributeValue.builder().s(pkValue).build());

        QueryRequest queryRequest = QueryRequest.builder()
                .keyConditionExpression(keyExpression)
                .expressionAttributeNames(expressionAttributesNames)
                .expressionAttributeValues(expressionAttributeValues)
                .limit(100)
                .scanIndexForward(false)
                .tableName(TABLE_NAME)
                .build();

        QueryResponse response = DYNAMODB_CLIENT.query(queryRequest);
        if(response.count() > 0 )
            return response.items().get(0).get("redirect_url").s();
        else
            return "";
    }

    public static String createUrl(String redirectUrl) {
        String hash = generateHash(redirectUrl);

        Map<String,AttributeValue> attributeValueMap = new HashMap<>();
        attributeValueMap.put("redirect_url", AttributeValue.builder().s(redirectUrl).build());
        attributeValueMap.put("hash", AttributeValue.builder().s(hash).build());

        PutItemResponse response = DYNAMODB_CLIENT.putItem(PutItemRequest.builder()
                .item(attributeValueMap)
                .returnConsumedCapacity(ReturnConsumedCapacity.TOTAL)
                .tableName(TABLE_NAME)
                .build());
        LOGGER.info("PutItem call consumed [{}] Write Capacity Unites (WCU)", response.consumedCapacity().capacityUnits());
        return hash;
    }

    private static String generateHash(String url) {
        return Integer.toHexString(url.hashCode()); // Simple hashing example
    }
}
