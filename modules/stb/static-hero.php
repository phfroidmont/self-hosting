<?php

/*
 * Plugin Name: STB static homepage hero
 * Description: Replaces the retired Slider Revolution homepage slide.
 */

if (!defined('ABSPATH')) {
    exit;
}

if (in_array('revslider/revslider.php', (array) get_option('active_plugins', []), true)) {
    return;
}

function putRevSlider($alias)
{
    if ($alias !== 'boxed') {
        return;
    }

    $background = esc_url(home_url('/wp-content/uploads/2018/02/bertrix-10m-011.jpg'));
    ?>
    <style>
        .stb-static-hero {
            aspect-ratio: 1320 / 650;
            background-image: url('<?php echo $background; ?>');
            background-position: center top;
            background-repeat: no-repeat;
            background-size: cover;
            color: #fff;
            overflow: hidden;
            position: relative;
            width: 100%;
        }

        .stb-static-hero__title,
        .stb-static-hero__text,
        .stb-static-hero__actions {
            left: 7.58%;
            position: absolute;
        }

        .stb-static-hero__title {
            background: rgba(0, 0, 0, 0.5);
            border-radius: 2px;
            color: #fff;
            font-family: chunkfiveregular, serif;
            font-size: clamp(20px, 3.18vw, 42px);
            font-weight: 400;
            line-height: 1.05;
            margin: 0;
            padding: 12px;
            top: 31.7%;
        }

        .stb-static-hero__text {
            background: rgba(0, 0, 0, 0.5);
            border-radius: 2px;
            font-size: clamp(13px, 1.36vw, 18px);
            line-height: 1.55;
            margin: 0;
            padding: 12px;
            top: 44.6%;
        }

        .stb-static-hero__actions {
            display: flex;
            gap: 8px;
            top: 62.6%;
        }

        .stb-static-hero__actions .btn,
        .stb-static-hero__actions .btn-2 {
            font-size: clamp(13px, 1.52vw, 20px);
            line-height: 1.1;
            margin: 0;
            padding: clamp(10px, 1.5vw, 20px) clamp(14px, 2.5vw, 33px);
            white-space: nowrap;
        }

        @media (max-width: 600px) {
            .stb-static-hero {
                aspect-ratio: auto;
                min-height: 300px;
            }

            .stb-static-hero__title,
            .stb-static-hero__text,
            .stb-static-hero__actions {
                left: 5%;
            }

            .stb-static-hero__title {
                top: 19%;
            }

            .stb-static-hero__text {
                top: 38%;
            }

            .stb-static-hero__actions {
                top: 66%;
            }
        }
    </style>
    <section class="stb-static-hero" aria-label="La Société de Tir Bertrix">
        <h1 class="stb-static-hero__title">La Société de Tir Bertrix</h1>
        <p class="stb-static-hero__text">
            Un Club de tir sportif convivial en plein<br>
            coeur de la province du Luxembourg.
        </p>
        <div class="stb-static-hero__actions">
            <a href="<?php echo esc_url(home_url('/le-club/devenir-membre/')); ?>" class="tp-button btn">Devenir membre</a>
            <a href="<?php echo esc_url(home_url('/le-club/')); ?>" class="tp-button btn-2">En savoir plus</a>
        </div>
    </section>
    <?php
}
