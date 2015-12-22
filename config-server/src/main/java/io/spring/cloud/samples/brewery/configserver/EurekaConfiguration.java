package io.spring.cloud.samples.brewery.configserver;

import org.springframework.cloud.client.discovery.EnableDiscoveryClient;
import org.springframework.context.annotation.Configuration;
import org.springframework.context.annotation.Profile;

@Configuration
@Profile("eureka")
@EnableDiscoveryClient
public class EurekaConfiguration {
}
