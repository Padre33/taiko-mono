package rabbitmq

import (
	"context"
	"fmt"
	"log/slog"
	"sync"
	"time"

	"github.com/google/uuid"
	amqp "github.com/rabbitmq/amqp091-go"
	"github.com/taikoxyz/taiko-mono/packages/relayer/pkg/queue"
)

type RabbitMQ struct {
	conn  *amqp.Connection
	ch    *amqp.Channel
	queue amqp.Queue
	opts  queue.NewQueueOpts

	connErrCh chan *amqp.Error

	chErrCh chan *amqp.Error

	notifyReturnCh chan amqp.Return

	subscriptionCtx    context.Context
	subscriptionCancel context.CancelFunc
}

func NewQueue(opts queue.NewQueueOpts) (*RabbitMQ, error) {
	slog.Info("dialing rabbitmq connection")

	r := &RabbitMQ{
		opts: opts,
	}

	err := r.connect()
	if err != nil {
		return nil, err
	}

	return r, nil
}

func (r *RabbitMQ) connect() error {
	slog.Info("connecting to rabbitmq")

	if r.subscriptionCancel != nil {
		r.subscriptionCancel()
	}

	conn, err := amqp.DialConfig(
		fmt.Sprintf(
			"amqp://%v:%v@%v:%v/",
			r.opts.Username,
			r.opts.Password,
			r.opts.Host,
			r.opts.Port,
		), amqp.Config{
			Heartbeat: 1 * time.Second,
		})
	if err != nil {
		return err
	}

	ch, err := conn.Channel()
	if err != nil {
		return err
	}

	if err := ch.Qos(int(r.opts.PrefetchCount), 0, false); err != nil {
		return err
	}

	r.conn = conn
	r.ch = ch

	r.connErrCh = r.conn.NotifyClose(make(chan *amqp.Error, 1))

	r.chErrCh = r.ch.NotifyClose(make(chan *amqp.Error, 1))

	r.subscriptionCtx, r.subscriptionCancel = context.WithCancel(context.Background())

	slog.Info("connected to rabbitmq")

	return nil
}

func (r *RabbitMQ) Start(ctx context.Context, queueName string) error {
	slog.Info("declaring rabbitmq queue", "queue", queueName)

	q, err := r.ch.QueueDeclare(
		queueName,
		true,
		false,
		false,
		false,
		nil,
	)
	if err != nil {
		return err
	}

	r.queue = q

	return nil
}

func (r *RabbitMQ) Close(ctx context.Context) {
	if err := r.ch.Close(); err != nil {
		if err != amqp.ErrClosed {
			slog.Info("error closing rabbitmq connection", "err", err.Error())
		}
	}

	slog.Info("closed rabbitmq channel")

	if err := r.conn.Close(); err != nil {
		if err != amqp.ErrClosed {
			slog.Info("error closing rabbitmq connection", "err", err.Error())
		}
	}

	slog.Info("closed rabbitmq connection")
}

func (r *RabbitMQ) Publish(ctx context.Context, msg []byte) error {
	slog.Info("publishing rabbitmq msg to queue", "queue", r.queue.Name)

	err := r.ch.PublishWithContext(ctx,
		"",
		r.queue.Name,
		true,
		false,
		amqp.Publishing{
			ContentType: "text/plain",
			Body:        msg,
			MessageId:   uuid.New().String(),
		})
	if err != nil {
		if err == amqp.ErrClosed {
			slog.Error("amqp channel closed", "err", err.Error())

			err := r.connect()
			if err != nil {
				return err
			}

			return r.Publish(ctx, msg)
		} else {
			return err
		}
	}

	return nil
}

func (r *RabbitMQ) Ack(ctx context.Context, msg queue.Message) error {
	rmqMsg := msg.Internal.(amqp.Delivery)

	slog.Info("acknowledging rabbitmq message", "msgId", rmqMsg.MessageId)

	err := rmqMsg.Ack(false)

	slog.Info("attempted acknowledge rabbitmq message")

	if err != nil {
		slog.Error("error acknowledging rabbitmq message", "err", err.Error())
		return err
	}

	slog.Info("acknowledged rabbitmq message", "msgId", rmqMsg.MessageId)

	return nil
}

func (r *RabbitMQ) Nack(ctx context.Context, msg queue.Message) error {
	rmqMsg := msg.Internal.(amqp.Delivery)

	slog.Info("negatively acknowledging rabbitmq message", "msgId", rmqMsg.MessageId)

	err := rmqMsg.Nack(false, false)
	if err != nil {
		slog.Error("error negatively acknowledging rabbitmq message", "err", err.Error())
		return err
	}

	slog.Info("negatively acknowledged rabbitmq message", "msgId", rmqMsg.MessageId)

	return nil
}

// Notify should be called by publishers who wish to be notified of subscription errors.
func (r *RabbitMQ) Notify(ctx context.Context, wg *sync.WaitGroup) error {
	wg.Add(1)

	defer func() {
		wg.Done()
	}()

	slog.Info("rabbitmq notify running")

	for {
		select {
		case <-ctx.Done():
			slog.Info("rabbitmq context closed")

			return nil
		case err := <-r.connErrCh:
			slog.Error("rabbitmq notify close connection", "err", err.Error())
			return queue.ErrClosed
		case err := <-r.chErrCh:
			slog.Error("rabbitmq notify close channel", "err", err.Error())
			return queue.ErrClosed
		case returnMsg := <-r.notifyReturnCh:
			slog.Error("rabbitmq notify return", "id", returnMsg.MessageId, "err", returnMsg.ReplyText)
			slog.Info("rabbitmq attempting republish of returned msg", "id", returnMsg.MessageId)

			if err := r.Publish(ctx, returnMsg.Body); err != nil {
				slog.Error("error publishing msg", "err", err.Error())
			}
		}
	}
}

// Subscribe should be called by consumers.
func (r *RabbitMQ) Subscribe(ctx context.Context, msgChan chan<- queue.Message, wg *sync.WaitGroup) error {
	wg.Add(1)

	defer func() {
		wg.Done()
	}()

	slog.Info("subscribing to rabbitmq messages", "queue", r.queue.Name)

	msgs, err := r.ch.Consume(
		r.queue.Name,
		"",
		false, // disable auto-acknowledge until after processing
		false,
		false,
		false,
		nil,
	)

	if err != nil {
		if err == amqp.ErrClosed {
			slog.Info("cant subscribe to rabbitmq, channel closed. attempting reconnection")

			if err := r.connect(); err != nil {
				slog.Error("error reconnecting to channel during subscribe", "err", err.Error())
				return err
			}

			msgs, err = r.ch.Consume(
				r.queue.Name,
				"",
				false, // disable auto-acknowledge until after processing
				false,
				false,
				false,
				nil,
			)
			if err != nil {
				return err
			}
		} else {
			return err
		}
	}

	for {
		select {
		case <-r.subscriptionCtx.Done():
			defer r.Close(ctx)

			slog.Info("rabbitmq subscription ctx cancelled")

			return queue.ErrClosed
		case <-ctx.Done():
			defer r.Close(ctx)

			slog.Info("rabbitmq context cancelled")

			return nil
		case err := <-r.connErrCh:
			slog.Error("rabbitmq notify close connection", "err", err.Error())

			return queue.ErrClosed
		case err := <-r.chErrCh:
			slog.Error("rabbitmq notify close channel", "err", err.Error())

			return queue.ErrClosed
		case d, ok := <-msgs:
			if !ok {
				slog.Error("rabbitmq msg channel was closed")
				return queue.ErrClosed
			}

			if d.Body != nil {
				slog.Info("rabbitmq message found", "msgId", d.MessageId)

				msgChan <- queue.Message{
					Body:     d.Body,
					Internal: d,
				}
			} else {
				slog.Info("nil body message, queue is closed")
				return queue.ErrClosed
			}
		}
	}
}
