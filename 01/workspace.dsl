workspace "Сервис доставки" "Архитектура системы сервиса доставки" {

    model {
        sender = person "Отправитель" "Пользователь, который создаёт предметы и инициирует доставку"
        receiver = person "Получатель" "Пользователь, который получает предметы и отслеживает доставку"
        admin = person "Администратор" "Управляет пользователями и данными системы"


        emailSystem = softwareSystem "Email/SMS Сервис" "Отправка уведомлений пользователям" "External"
        paymentSystem = softwareSystem "Платёжная система" "Обработка платежей за доставку" "External"
        geoService = softwareSystem "Геолокационный сервис" "Отслеживание местоположения предмета" "External"


        deliveryPlatform = softwareSystem "Сервис доставки" "Платформа для создания предметов и управления доставками между пользователями" {

            webApp = container "Web Application" "Пользовательский интерфейс для работы с сервисом доставки" "React/TypeScript" "WebBrowser"

            apiGateway = container "API Gateway" "Единая точка входа. Маршрутизация, аутентификация, rate limiting" "Nginx" "Gateway"

            userService = container "User Service" "Управление пользователями: регистрация, поиск по логину, поиск по маске имени и фамилии" "C++ / userver" "Service"

            itemService = container "Item Service" "Управление посылками: создание посылок, получение посылок пользователя" "C++ / userver" "Service"

            deliveryService = container "Delivery Service" "Управление доставками: создание доставки, получение информации по получателю/отправителю, оплата, отслеживание" "C++ / userver" "Service"

            notificationService = container "Notification Service" "Отправка уведомлений о статусе доставки" "C++ / userver" "Service"

            messageBroker = container "Message Broker" "Асинхронный обмен событиями между сервисами" "Apache Kafka" "Queue"

            userDb = container "User Database" "Хранение данных пользователей" "PostgreSQL" "Database"
            itemDb = container "Item Database" "Хранение данных посылок" "PostgreSQL" "Database"
            deliveryDb = container "Delivery Database" "Хранение данных доставок" "PostgreSQL" "Database"
        }

        sender -> deliveryPlatform "Создаёт предметы и доставки" "HTTPS"
        receiver -> deliveryPlatform "Просматривает доставки и предметы" "HTTPS"
        admin -> deliveryPlatform "Управляет пользователями" "HTTPS"

        deliveryPlatform -> emailSystem "Отправляет уведомления" "SMTP/HTTPS"
        deliveryPlatform -> paymentSystem "Обрабатывает платежи" "HTTPS/REST"
        deliveryPlatform -> geoService "Запрашивает геолокацию" "HTTPS/REST"


        sender -> webApp "Создаёт предметы и доставки" "HTTPS"
        receiver -> webApp "Отслеживает доставки" "HTTPS"
        admin -> webApp "Управляет пользователями" "HTTPS"

        webApp -> apiGateway "Отправляет API-запросы" "HTTPS/REST (JSON)"

        apiGateway -> userService "Маршрутизирует запросы пользователей" "HTTPS/REST"
        apiGateway -> itemService "Маршрутизирует запросы предметов" "HTTPS/REST"
        apiGateway -> deliveryService "Маршрутизирует запросы доставок" "HTTPS/REST"

        userService -> userDb "Читает и записывает данные пользователей" "SQL"
        itemService -> itemDb "Читает и записывает данные предметов" "SQL"
        deliveryService -> deliveryDb "Читает и записывает данные доставок" "SQL"


        deliveryService -> userService "Проверяет существование отправителя и получателя" "HTTPS/REST"
        deliveryService -> itemService "Проверяет существование предмета" "HTTPS/REST"


        deliveryService -> paymentSystem "Инициирует оплату доставки" "HTTPS/REST"
        deliveryService -> geoService "Запрашивает текущее местоположение предмета" "HTTPS/REST"


        deliveryService -> messageBroker "Публикует 'DeliveryCreated', 'DeliveryStatusChanged'" "Kafka Protocol"
        itemService -> messageBroker "Публикует 'ItemCreated'" "Kafka Protocol"
        notificationService -> messageBroker "Подписывается на события" "Kafka Protocol"

        notificationService -> emailSystem "Отправляет email/SMS уведомления" "SMTP/HTTPS"
    }

    views {
        # ===== System Context (C1) =====
        systemContext deliveryPlatform "SystemContext" {
            include *
            autoLayout
            description "Диаграмма контекста системы Сервис доставки"
        }

        # ===== Container (C2) =====
        container deliveryPlatform "Containers" {
            include *
            autoLayout
            description "Диаграмма контейнеров системы Сервис доставки"
        }

        # Создание доставки
        dynamic deliveryPlatform "CreateDelivery" "Сценарий: Создание доставки от отправителя к получателю с оплатой" {
            sender -> webApp "Заполняет форму создания доставки"
            webApp -> apiGateway "POST /api/delivery {senderId, receiverId, itemIds}"
            apiGateway -> deliveryService "Передаёт запрос на создание доставки"
            deliveryService -> userService "Проверяет отправителя (GET /user/{senderId})"
            deliveryService -> userService "Проверяет получателя (GET /user/{receiverId})"
            deliveryService -> itemService "Проверяет посылку (GET /item/{itemId})"
            deliveryService -> paymentSystem "Инициирует оплату доставки"
            deliveryService -> deliveryDb "Сохраняет запись о доставке"
            deliveryService -> messageBroker "Публикует событие 'DeliveryCreated'"
            notificationService -> messageBroker "Получает событие 'DeliveryCreated'"
            notificationService -> emailSystem "Отправляет уведомление получателю"
            autoLayout
        }

        # Отслеживание предмета
        dynamic deliveryPlatform "TrackDelivery" "Сценарий: Получатель отслеживает местоположение предмета" {
            receiver -> webApp "Открывает страницу отслеживания доставки"
            webApp -> apiGateway "GET /api/delivery/{id}/tracking"
            apiGateway -> deliveryService "Передаёт запрос на отслеживание"
            deliveryService -> deliveryDb "Получает трек-номер доставки по deliveryId"
            deliveryService -> geoService "Запрашивает геолокацию по трек-номеру"
            deliveryService -> apiGateway "Возвращает актуальные координаты"
            deliveryService -> geoService "Запрашивает информацию о геолокаций"
            apiGateway -> webApp "Передаёт данные о местоположении"
            webApp -> receiver "Отображает карту с текущим положением предмета"

            autoLayout
        }

        styles {
            element "Person" {
                shape Person
                background #08427B
                color #ffffff
            }
            element "Software System" {
                background #1168BD
                color #ffffff
            }
            element "External" {
                background #999999
                color #ffffff
            }
            element "Service" {
                shape RoundedBox
                background #438DD5
                color #ffffff
            }
            element "Database" {
                shape Cylinder
                background #82E0AA
                color #000000
            }
            element "Queue" {
                shape Pipe
                background #7B8D8E
                color #ffffff
            }
            element "Gateway" {
                shape RoundedBox
                background #2E86C1
                color #ffffff
            }
            element "WebBrowser" {
                shape WebBrowser
                background #438DD5
                color #ffffff
            }
        }
    }
}